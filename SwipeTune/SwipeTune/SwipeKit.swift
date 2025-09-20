import SwiftUI
import AVFoundation
import Combine

// MARK: - Dreamy Aesthetic (palette + helpers)
private struct Palette {
    static let grad = LinearGradient(
        colors: [
            Color(hue: 0.76, saturation: 0.72, brightness: 0.88), // lavender
            Color(hue: 0.86, saturation: 0.60, brightness: 0.92), // pinkish violet
            Color(hue: 0.64, saturation: 0.55, brightness: 0.90)  // periwinkle
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let aura1 = LinearGradient(
        colors: [Color.purple.opacity(0.30), Color.pink.opacity(0.18)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let aura2 = LinearGradient(
        colors: [Color.blue.opacity(0.20), Color.purple.opacity(0.24)],
        startPoint: .bottomLeading, endPoint: .topTrailing
    )
}

// Gradient text helper
private extension View {
    func gradientText() -> some View { self.foregroundStyle(Palette.grad) }
}

// Glassy gradient-stroke button
private struct GlassGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 26).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Palette.grad, lineWidth: 2)
            )
            .shadow(color: .purple.opacity(configuration.isPressed ? 0.12 : 0.18),
                    radius: configuration.isPressed ? 8 : 16, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}


// MARK: - Model
struct Song: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artist: String
    let artworkURL: URL?
    let previewURL: URL? // 30s preview if available
}

// Simple in-memory store for likes/passes
final class SwipeStore: ObservableObject {
    @Published var deck: [Song]
    @Published var liked: [Song] = []
    @Published var passed: [Song] = []

    init(deck: [Song]) { self.deck = deck }

    func swipe(_ song: Song, like: Bool) {
        guard let idx = deck.firstIndex(of: song) else { return }
        _ = deck.remove(at: idx)
        if like { liked.append(song) } else { passed.append(song) }
    }

    func reset(with songs: [Song]) {
        deck = songs
        liked.removeAll(); passed.removeAll()
    }
}

// MARK: - Audio Preview
final class PreviewPlayer: ObservableObject {
    private var player: AVPlayer?
    @Published var isPlaying = false

    func play(url: URL?) {
        guard let url else { return }
        if let player, isPlaying {
            player.pause(); isPlaying = false
        }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func stop() { player?.pause(); isPlaying = false }
}

// MARK: - Swipe Card
struct SongCard: View {
    let song: Song
    let onRemove: (_ like: Bool) -> Void

    @State private var translation: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var isDragging = false

    private var threshold: CGFloat { 120 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: song.artworkURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    Text(song.artist)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(radius: 2)
                }
                .padding(16)
            }
            .cornerRadius(20)
            .shadow(radius: 12, y: 6)
            .offset(x: translation.width, y: translation.height)
            .rotationEffect(.degrees(rotation))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        isDragging = true
                        translation = value.translation
                        rotation = Double(translation.width / geo.size.width) * 15
                    }
                    .onEnded { value in
                        let like = value.translation.width > threshold
                        let pass = value.translation.width < -threshold
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if like {
                                translation = CGSize(width: geo.size.width * 1.5, height: -40)
                                rotation = 20
                                onRemove(true)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } else if pass {
                                translation = CGSize(width: -geo.size.width * 1.5, height: -40)
                                rotation = -20
                                onRemove(false)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else {
                                translation = .zero; rotation = 0; isDragging = false
                            }
                        }
                    }
            )
            .overlay(alignment: .topLeading) {
                HStack {
                    if translation.width > 20 {
                        LabelBadge(text: "LIKE", color: .green)
                            .opacity(min(1, Double(abs(translation.width) / threshold)))
                    }
                    Spacer()
                    if translation.width < -20 {
                        LabelBadge(text: "NOPE", color: .red)
                            .opacity(min(1, Double(abs(translation.width) / threshold)))
                    }
                }
                .padding(16)
            }
        }
    }
}

struct LabelBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.headline.bold())
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.grad, lineWidth: 2)
            )
            .foregroundStyle(color) // keep the green/red text color for LIKE/NOPE
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .rotationEffect(.degrees(-10))
            .shadow(color: .purple.opacity(0.18), radius: 6)
    }
}

// MARK: - Deck View
struct SongSwipeDeck: View {
    @ObservedObject var store: SwipeStore
    @StateObject private var player = PreviewPlayer()

    var body: some View {
        ZStack {
            ForEach(Array(store.deck.enumerated()), id: \.element.id) { idx, song in
                SongCard(song: song) { like in
                    withAnimation {
                        store.swipe(song, like: like)
                    }
                }
                .padding(20)
                .zIndex(Double(idx))
                .scaleEffect(1 - (CGFloat(idx) * 0.02))
                .offset(y: CGFloat(idx) * 8)
            }

            if store.deck.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list").font(.largeTitle)
                    Text("You're all caught up!")
                    Button("Reset Demo Deck") { store.reset(with: DemoData.songs) }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                .shadow(radius: 10)
            
            }
        }
        .padding(.bottom,50)
        .onChange(of: store.deck.first?.previewURL) { _, url in
            // Auto-play preview for the top card if available
            player.play(url: url)
        }
    }

    private func manualSwipe(like: Bool) {
        guard let top = store.deck.first else { return }
        withAnimation(.spring()) { store.swipe(top, like: like) }
        UIImpactFeedbackGenerator(style: like ? .medium : .light).impactOccurred()
    }
}

struct ControlButton: View {
    let icon: String
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().stroke(Palette.grad, lineWidth: 2))
            .overlay(Image(systemName: icon).font(.title3).foregroundStyle(.primary))
            .frame(width: 60, height: 60)
            .shadow(color: .purple.opacity(0.18), radius: 16, x: 0, y: 8)
    }
    }

// MARK: - Demo + Previews
enum DemoData {
    static let songs: [Song] = [
        Song(title: "Midnight City", artist: "M83", artworkURL: URL(string: "https://picsum.photos/seed/a/600/600"), previewURL: nil),
        Song(title: "Blinding Lights", artist: "The Weeknd", artworkURL: URL(string: "https://picsum.photos/seed/b/600/600"), previewURL: nil),
        Song(title: "Levitating", artist: "Dua Lipa", artworkURL: URL(string: "https://picsum.photos/seed/c/600/600"), previewURL: nil),
        Song(title: "Sunflower", artist: "Post Malone", artworkURL: URL(string: "https://picsum.photos/seed/d/600/600"), previewURL: nil),
        Song(title: "Heat Waves", artist: "Glass Animals", artworkURL: URL(string: "https://picsum.photos/seed/e/600/600"), previewURL: nil)
    ]
}

// MARK: - SongSwipeHome
struct SongSwipeHome: View {
    @StateObject private var store = SwipeStore(deck: DemoData.songs)
    
    // State for animations
    @State private var logoOpacity: Double = 0
    @State private var logoAtTop: Bool = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Gradient Title
                Text("Spinder")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.grad) // ✅ Gradient applied
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .opacity(logoOpacity)
                    .padding(.top, logoAtTop ? 10 : 64)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.7)) { logoOpacity = 1 }
                    }
                
                // Swipe deck
                SongSwipeDeck(store: store)
                    .frame(maxHeight: .infinity)
            }
            .toolbar {
                NavigationLink {
                    LikedListView(liked: store.liked)
                } label: {
                    Image(systemName: "heart")
                }
            }
        }
    }
}


struct LikedListView: View {
    let liked: [Song]
    var body: some View {
        List(liked) { s in
            HStack(spacing: 12) {
                AsyncImage(url: s.artworkURL) { img in img.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(s.title).font(.headline)
                    Text(s.artist).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Liked")
    }
}

#Preview {
    SongSwipeHome()
}

// MARK: - Integration Notes
/*
Next steps to make this production:

1) Apple Music (MusicKit) or Spotify:
   - Apple: request MusicKit entitlement, use MusicCatalogSearchRequest to fetch tracks, get artworkURL and previewURL (Apple provides 30s previews) and MusicPlayer for playback.
   - Spotify: use Web API for search/recs and Playback SDK for in-app (Premium required). Store access tokens securely.

2) Recommendations:
   - Start with Spotify's /recommendations endpoint or Apple's personalized stations.
   - After each swipe, send feedback to a lightweight service (e.g., Supabase/Firestore) and update seed artists/genres.

3) Persistence:
   - Save likes/passes locally (Core Data) + optional sync (CloudKit or your backend) tied to user id.

4) Rate limits & caching:
   - Cache artwork with URLCache or Nuke. Batch fetch tracks.

5) UX polish:
   - Add rewind, super-like, skip animations, queue previews only when on top card.
   - Haptics tuned with UINotificationFeedbackGenerator.

6) Legal:
   - Check ToS for playback/preview rules. Full-track playback varies by provider and subscription.
*/

// MARK: - Onboarding (Playlist Link Import)
protocol MusicProvider {
    func importPlaylist(from url: URL) async throws -> [Song]
}

enum PlaylistImportError: LocalizedError {
    case unsupported
    case invalidURL
    case network
    case authRequired
    case parsing

    var errorDescription: String? {
        switch self {
        case .unsupported: return "Unsupported playlist link. Use Apple Music or Spotify."
        case .invalidURL: return "That doesn't look like a valid playlist URL."
        case .network: return "Network error while fetching playlist."
        case .authRequired: return "Please sign in to your music provider."
        case .parsing: return "Couldn't parse playlist tracks."
        }
    }
}

// MARK: - Providers (stubs)
struct SpotifyProvider: MusicProvider {
    func importPlaylist(from url: URL) async throws -> [Song] {
        guard let _ = PlaylistLinkParser.spotifyPlaylistID(from: url) else { throw PlaylistImportError.invalidURL }
        // TODO: Call your backend proxy → Spotify /playlists/{id}
        return DemoData.songs.shuffled()
    }
}

struct AppleMusicProvider: MusicProvider {
    func importPlaylist(from url: URL) async throws -> [Song] {
        guard let _ = PlaylistLinkParser.applePlaylistID(from: url) else { throw PlaylistImportError.invalidURL }
        // TODO: Call your backend proxy → Apple Music /playlists/{id}
        return DemoData.songs
    }
}

// MARK: - Link Parser
enum PlaylistLinkParser {
    // e.g. https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
    static func spotifyPlaylistID(from url: URL) -> String? {
        guard url.host?.contains("spotify.com") == true else { return nil }
        let comps = url.pathComponents // ["/", "playlist", "{id}"]
        guard comps.count >= 3, comps[1] == "playlist" else { return nil }
        return comps[2]
    }

    // e.g. https://music.apple.com/us/playlist/alt-pop/pl.XXXXXXXX
    static func applePlaylistID(from url: URL) -> String? {
        guard let host = url.host, host.contains("music.apple.com") else { return nil }
        let comps = url.pathComponents // ["/", "us", "playlist", "name", "pl.xxxxx"]
        guard let plIndex = comps.firstIndex(of: "playlist"), comps.count > plIndex + 1 else { return nil }
        return comps.last?.hasPrefix("pl.") == true ? comps.last : nil
    }

    static func provider(for url: URL) -> MusicProvider? {
        if url.host?.contains("spotify.com") == true { return SpotifyProvider() }
        if url.host?.contains("music.apple.com") == true { return AppleMusicProvider() }
        return nil
    }
}

// MARK: - Onboarding UI to paste a playlist link
struct PlaylistLinkOnboarding: View {
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let onImported: ([Song]) -> Void

    var body: some View {
        ZStack {
            // Transparent background so the sheet blends with onboarding
            Color.clear.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Bring Your Playlist")
                    .font(.title.bold())
                    .foregroundStyle(Palette.grad)   // ← replaces .gradientText()

                Text("Paste a Spotify playlist link to seed recommendations.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                // Input field
                TextField("https://open.spotify.com/playlist/...", text: $input)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.purple.opacity(0.5), Color.indigo.opacity(0.5)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .foregroundColor(.gray) // link font color gray

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                // Primary button
                Button {
                    importLink()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView() }
                        Text(isLoading ? "Importing…" : "Use This Playlist").bold()
                    }
                    .foregroundStyle(.black)
                }
                .buttonStyle(GlassGradientButtonStyle())
                .disabled(isLoading || URL(string: input) == nil)

                Button("Skip for now") { dismiss() }
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }


    private func importLink() {
        error = nil
        guard let url = URL(string: input) else { error = PlaylistImportError.invalidURL.localizedDescription; return }
        guard let provider = PlaylistLinkParser.provider(for: url) else { error = PlaylistImportError.unsupported.localizedDescription; return }
        isLoading = true
        Task { @MainActor in
            do {
                let songs = try await provider.importPlaylist(from: url)
                onImported(songs)
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Root Flow wiring example
struct RootAppView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @StateObject private var store = SwipeStore(deck: DemoData.songs)
    @State private var showPlaylistOnboarding = false

    var body: some View {
        NavigationStack {
            Group {
                if didOnboard {
                    SongSwipeHome()
                } else {
                    VStack(spacing: 20) {
                        Text("Welcome to TuneSwipe 🎵")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Swipe to like songs. Start by importing a playlist to personalize recommendations.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Import Playlist Link") { showPlaylistOnboarding = true }
                            .buttonStyle(.borderedProminent)
                        Button("Continue with Demo Deck") { didOnboard = true }
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showPlaylistOnboarding) {
                PlaylistLinkOnboarding { songs in
                    store.reset(with: songs)
                    didOnboard = true
                }
            }
        }
    }
}
