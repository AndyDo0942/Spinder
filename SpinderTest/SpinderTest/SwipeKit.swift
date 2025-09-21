import SwiftUI
import AVFoundation
import WebKit
import Combine

import Foundation

// MARK: - URL Parsing
func extractPlaylistID(from urlString: String) -> String? {
    // Handle various Spotify URL formats:
    // https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
    // spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
    // 37i9dQZF1DXcBWIGoYBM5M (just the ID)
    
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // If it's already just an ID (22 characters, alphanumeric)
    if trimmed.count == 22 && trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
        return trimmed
    }
    
    // Extract from URL patterns
    let patterns = [
        "playlist/([a-zA-Z0-9]{22})",  // open.spotify.com/playlist/ID
        "spotify:playlist:([a-zA-Z0-9]{22})"  // spotify:playlist:ID
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = regex.firstMatch(in: trimmed, range: range),
               let idRange = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[idRange])
            }
        }
    }
    
    return nil
}

struct Song: Identifiable, Codable, Hashable {
    let id: String       // we'll map spotify_id here
    let name: String
    let artists: [String]
    let imageURL: String
    
    // Computed properties for compatibility with existing UI code
    var title: String { name }
    var artistDisplay: String { artists.joined(separator: ", ") }
    var artworkURL: URL? {
        print("🔍 Processing imageURL: '\(imageURL)'")
        let url = URL(string: imageURL)
        if url == nil {
            print("⚠️ Invalid imageURL: '\(imageURL)'")
        } else {
            print("✅ Valid imageURL: \(url!.absoluteString)")
        }
        return url
    }
    var spotifyID: String { id }

    enum CodingKeys: String, CodingKey {
        case id = "spotify_id"
        case name
        case artists = "artist"  // Backend returns "artist" but we want "artists"
        case imageURL = "image_url"
    }
    
    // Memberwise initializer for creating songs manually
    init(id: String, name: String, artists: [String], imageURL: String) {
        self.id = id
        self.name = name
        self.artists = artists
        self.imageURL = imageURL
    }
    
    // Minimal custom decoder to handle missing spotify_id
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle missing spotify_id with a simple fallback
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? "missing_id_\(Int.random(in: 1000...9999))"
        self.name = try container.decode(String.self, forKey: .name)
        self.artists = try container.decode([String].self, forKey: .artists)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? "https://via.placeholder.com/300x300/1DB954/FFFFFF?text=Music"
    }
}

enum BackendClient {
    // TODO: change base to your Flask host
    static let base = URL(string: "http://127.0.0.1:5000")!

    static func fetchRecommendedSongs(playlistId: String = "54ZA9LXFvvFujmOVWXpHga") async throws -> [Song] {
        let url = base.appendingPathComponent("link").appendingPathComponent(playlistId)
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode([Song].self, from: data)
        return decoded
    }
}

// MARK: - Store
@MainActor
final class SwipeStore: ObservableObject {
    @Published var deck: [Song]
    @Published var liked: [Song] = []
    @Published var passed: [Song] = []
    @Published var isLoading = false
    @Published var isSendingLiked = false
    @Published var errorMessage: String?
    @AppStorage("currentPlaylistID") private var currentPlaylistID: String = "54ZA9LXFvvFujmOVWXpHga"
    
    // Track which songs have been sent to backend to prevent duplicates
    private var sentSongIDs: Set<String> = []

    init(deck: [Song]) { self.deck = deck }

    func swipe(_ song: Song, like: Bool) {
        guard let idx = deck.firstIndex(of: song) else { return }
        _ = deck.remove(at: idx)
        if like { liked.append(song) } else { passed.append(song) }
        
        print("🎵 Swiped \(like ? "liked" : "passed"): \(song.name) - Deck count: \(deck.count), Liked count: \(liked.count)")
        
        // Check if deck is empty and we have liked songs to send
        if deck.isEmpty && !liked.isEmpty {
            print("🔄 Deck is empty, triggering sendLikedSongsToBackend...")
            Task {
                await sendLikedSongsToBackend()
            }
        }
    }

    func reset(with songs: [Song]) {
        deck = songs
        liked.removeAll(); passed.removeAll()
    }

    func loadFromBackend() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let songs = try await fetchSongs(for: currentPlaylistID)
            print("🔄 Loaded \(songs.count) new songs from backend")
            
            // Debug: Check image URLs
            for (index, song) in songs.prefix(3).enumerated() {
                print("🎵 Song \(index + 1): \(song.name)")
                print("   Image URL: '\(song.imageURL)'")
                print("   Artwork URL: \(song.artworkURL?.absoluteString ?? "nil")")
                print("   Spotify ID: \(song.spotifyID)")
            }
            
            reset(with: songs)
        } catch {
            print("Fetch error:", error)
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func sendLikedSongsToBackend() async {
        guard !liked.isEmpty && !isSendingLiked else { 
            print("⚠️ Skipping sendLikedSongsToBackend - liked.isEmpty: \(liked.isEmpty), isSendingLiked: \(isSendingLiked)")
            return 
        }
        
        // Only send songs that haven't been sent before
        let unsentSongs = liked.filter { !sentSongIDs.contains($0.spotifyID) }
        guard !unsentSongs.isEmpty else { 
            print("⚠️ No unsent songs to send")
            return 
        }
        
        print("📤 Sending \(unsentSongs.count) unsent songs to backend...")
        isSendingLiked = true
        
        do {
            // Send liked songs and get new recommendations in one call
            let newSongs = try await postLikedSongsAndGetRecommendations(unsentSongs)
            print("✅ Successfully sent \(unsentSongs.count) liked songs and got \(newSongs.count) new recommendations")
            
            // Mark these songs as sent
            for song in unsentSongs {
                sentSongIDs.insert(song.spotifyID)
            }
            
            // Update the deck with new recommendations
            if !newSongs.isEmpty {
                await MainActor.run {
                    deck = newSongs
                }
            }
        } catch {
            print("❌ Failed to send liked songs:", error)
            errorMessage = "Failed to send feedback. Please try again."
        }
        
        isSendingLiked = false
        print("✅ sendLikedSongsToBackend completed")
    }
    
    func updatePlaylistID(_ playlistID: String) {
        currentPlaylistID = playlistID
    }
    
    func resetEverything() {
        // Clear all local data
        deck = []
        liked.removeAll()
        passed.removeAll()
        sentSongIDs.removeAll()
        errorMessage = nil
        isLoading = false
        isSendingLiked = false
    }
}

// MARK: - Audio Preview (kept for future use)
final class PreviewPlayer: ObservableObject {
    private var player: AVPlayer?
    @Published var isPlaying = false

    func play(url: URL?) {
        guard let url else { return }
        if let player, isPlaying { player.pause(); isPlaying = false }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true
    }
    func toggle() { guard let p = player else { return }; isPlaying ? p.pause() : p.play(); isPlaying.toggle() }
    func stop() { player?.pause(); isPlaying = false }
}

// MARK: - Spotify 30s Embed
import SwiftUI
import WebKit

struct SpotifyEmbedView: UIViewRepresentable {
    let trackID: String
    /// 88–100 looks best. 96 is a good default.
    var height: CGFloat = 96

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.loadHTMLString(makeHTML(for: trackID, height: Int(height)), baseURL: nil)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(makeHTML(for: trackID, height: Int(height)), baseURL: nil)
    }

    private func makeHTML(for trackID: String, height: Int) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html,body{margin:0;padding:0;background:transparent;overflow:hidden;}
            .wrap{
              width:100%;
              height:\(height)px;
              border-radius:14px;
              overflow:hidden;
              background:transparent;
              position:relative;
            }
            iframe, #embed-iframe {
              position:absolute;
              inset:0;
              width:100%;
              height:100%;
              border:0;
            }
          </style>
          <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
        </head>
        <body>
          <div class="wrap">
            <div id="embed-iframe"></div>
          </div>
          <script>
            window.onSpotifyIframeApiReady = (IFrameAPI) => {
              const el = document.getElementById('embed-iframe');
              const options = { uri: 'spotify:track:\(trackID)', theme: 'dark' };
              IFrameAPI.createController(el, options, () => {});
            };
          </script>
        </body>
        </html>
        """
    }
}



// MARK: - Card
struct SongCard: View {
    let song: Song
    let onRemove: (_ like: Bool) -> Void

    @State private var translation: CGSize = .zero
    @State private var rotation: Double = 0

    private var threshold: CGFloat { 120 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                AsyncImage(
                    url: song.artworkURL,
                    transaction: Transaction(animation: .easeInOut(duration: 0.5))
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                            .onAppear {
                                print("✅ Image loaded successfully for: \(song.name)")
                                print("   URL: \(song.imageURL)")
                            }
                    case .failure(let error):
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.purple, .blue],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    Text("Image failed to load")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            )
                            .onAppear {
                                print("❌ Image failed for: \(song.name)")
                                print("   Error: \(error)")
                                print("   URL was: '\(song.imageURL)'")
                                print("   Artwork URL: \(song.artworkURL?.absoluteString ?? "nil")")
                            }
                    case .empty:
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .tint(.white)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .frame(width: 60, height: 60)
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 2
                                                        )
                                                )
                                        )
                                    Text("Loading...")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            )
                            .onAppear {
                                print("⏳ Loading image for: \(song.name)")
                                print("   URL: '\(song.imageURL)'")
                                print("   Artwork URL: \(song.artworkURL?.absoluteString ?? "nil")")
                                
                                // Test if the URL is actually accessible
                                if let url = song.artworkURL {
                                    Task {
                                        do {
                                            let (_, response) = try await URLSession.shared.data(from: url)
                                            if let httpResponse = response as? HTTPURLResponse {
                                                print("🌐 Image URL response: \(httpResponse.statusCode)")
                                            }
                                        } catch {
                                            print("❌ Image URL test failed: \(error)")
                                        }
                                    }
                                }
                            }
                    @unknown default:
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    }
                }
                .task(id: song.imageURL) {
                    // Force reload when image URL changes
                    print("🔄 AsyncImage task triggered for: \(song.name)")
                }
                .id("image-\(song.id)-\(song.imageURL)-\(Date().timeIntervalSince1970)") // Force complete re-render
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    Text(song.artistDisplay)
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
                                translation = .zero; rotation = 0
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.grad, lineWidth: 2))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .rotationEffect(.degrees(-10))
            .shadow(radius: 6)
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    let isLoading: Bool
    let isSendingLiked: Bool
    
    var body: some View {
        if isLoading || isSendingLiked {
            ZStack {
                // Clean white background with subtle purple gradient
                LinearGradient(
                    colors: [.white, .purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 24) {
                        // Enhanced progress indicator with liquid glass effect
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                )
                                .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 0)
                            
                            ProgressView()
                                .scaleEffect(1.8)
                                .tint(.purple)
                        }
                        
                        VStack(spacing: 12) {
                            Text(isSendingLiked ? "Sending your feedback..." : "Discovering new songs...")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            Text(isSendingLiked ? "We're learning from your preferences" : "This may take a moment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .padding(40)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: .purple.opacity(0.2), radius: 20, x: 0, y: 10)
                    )
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: isLoading || isSendingLiked)
        }
    }
}

// MARK: - Deck
struct SongSwipeDeck: View {
    @ObservedObject var store: SwipeStore

    @State private var currentTopID: String?

    var body: some View {
        ZStack {
            // Only show cards when not loading
            if !store.isLoading {
                ForEach(Array(store.deck.enumerated()), id: \.element.id) { idx, song in
                    SongCard(song: song) { like in
                        withAnimation { store.swipe(song, like: like) }
                    }
                    .padding(20)
                    // make sure top card draws on TOP visually (optional but nice)
                    .zIndex(Double(store.deck.count - idx))
                    .scaleEffect(1 - (CGFloat(idx) * 0.02))
                    .offset(y: CGFloat(idx) * 8)
                    .id("\(song.id)-\(song.imageURL)") // Force re-render when image URL changes
                }
            }

            if let errorMessage = store.errorMessage {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.red.opacity(0.4), .orange.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: .red.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.red, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 12) {
                        Text("Oops! Something went wrong")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    
                    Button("Try Again") {
                        Task {
                            await store.loadFromBackend()
                        }
                    }
                    .buttonStyle(GlassGradientButtonStyle())
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [.red.opacity(0.3), .orange.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .red.opacity(0.1), radius: 15, x: 0, y: 8)
                )
                .padding(.horizontal, 20)
                .padding(.top, 200)
            } else if store.deck.isEmpty && !store.isLoading && !store.isSendingLiked {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: .purple.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "music.note.list")
                            .font(.system(size: 30))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 12) {
                        Text("You're all caught up!")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text("Pull to refresh or try a different playlist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .purple.opacity(0.1), radius: 15, x: 0, y: 8)
                )
                .padding(.horizontal, 20)
                .padding(.top, 200)
            }
            
            // Loading overlay
            LoadingOverlay(isLoading: store.isLoading, isSendingLiked: store.isSendingLiked)
        }
        .onAppear {
            currentTopID = store.deck.first?.spotifyID
        }
        // whenever the top song changes (after a swipe), update the embed
        .onChange(of: store.deck.first?.id) { _, _ in
            currentTopID = store.deck.first?.spotifyID
        }
        // Embed for the top song (only show when not loading)
        .safeAreaInset(edge: .bottom) {
            if !store.isLoading, let id = currentTopID {
                SpotifyEmbedView(trackID: id, height: 96)
                    .id(id)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            } else {
                Spacer(minLength: 1)
            }
        }
    }
}


// MARK: - Demo


struct DemoData {
    static let songs: [Song] = [
        Song(
            id: "0VjIjW4GlUZAMYd2vXMi3b",
            name: "Blinding Lights",
            artists: ["The Weeknd"],
            imageURL: "https://i.scdn.co/image/ab67616d0000b273b8f7d4e8c58f21a8b4c9a46d"
        ),
        Song(
            id: "7ouMYWpwJ422jRcDASZB7P",
            name: "Levitating",
            artists: ["Dua Lipa"],
            imageURL: "https://i.scdn.co/image/ab67616d0000b2736f8a62e6a4c02187c9f2c1e1"
        ),
        Song(
            id: "4uLU6hMCjMI75M1A2tKUQC",
            name: "Never Gonna Give You Up",
            artists: ["Rick Astley"],
            imageURL: "https://i.scdn.co/image/ab67616d0000b273b664f645dd5bb0d9f2f1f3a0"
        )
    ]
}

// MARK: - Home
struct SongSwipeHome: View {
    // Start with demo data and load real data from backend
    @StateObject private var store = SwipeStore(deck: DemoData.songs)
    @AppStorage("currentPlaylistID") private var currentPlaylistID: String = "54ZA9LXFvvFujmOVWXpHga"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Title row
                HStack(spacing: -7) {
                    Text("Spinder")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .gradientText()                    // apply gradient to the text only

                    Image("SpinderLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 65, height: 65)      // smaller so it sits nicely with the text
                }
                .padding(.top, 10)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)

                SongSwipeDeck(store: store)
                    .padding(.top, 10)
            }
            .toolbar {
                NavigationLink {
                    LikedListView(store: store)
                } label: {
                    Image(systemName: "heart")
                }
            }
        }
        .task {
            // Load from your Flask backend once the view appears
            await store.loadFromBackend()
        }
        .onChange(of: currentPlaylistID) { _, newPlaylistID in
            // Reload data when playlist ID changes
            Task {
                await store.loadFromBackend()
            }
        }
        .refreshable {
            // Pull to refresh functionality
            await store.loadFromBackend()
        }
    }
}


struct LikedListView: View {
    @ObservedObject var store: SwipeStore
    @State private var showingEmptyState = false
    @State private var showingResetAlert = false
    @State private var showingPlaylistInput = false
    @State private var newPlaylistID = ""
    @State private var isResetting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            if store.liked.isEmpty {
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: .purple.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "heart.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 12) {
                        Text("No liked songs yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text("Start swiping to discover music you love!")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .purple.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .padding(.horizontal, 20)
                .navigationTitle("Liked Songs")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.liked) { song in
                            LikedSongRow(song: song)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .navigationTitle("Liked Songs (\(store.liked.count))")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingResetAlert = true
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Reset and Start Over")
                    }
                }
            }
        }
        .overlay {
            if isResetting {
                ZStack {
                    // Clean white background with purple gradient
                    LinearGradient(
                        colors: [.white, .purple.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 24) {
                            // Enhanced reset progress indicator
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.purple.opacity(0.7), .blue.opacity(0.7)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 3
                                            )
                                    )
                                    .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 0)
                                
                                ProgressView()
                                    .scaleEffect(1.8)
                                    .tint(.purple)
                            }
                            
                            VStack(spacing: 12) {
                                Text("Starting Fresh...")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                
                                Text("Clearing data and loading new playlist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: .purple.opacity(0.3), radius: 25, x: 0, y: 15)
                        )
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
                .zIndex(9999) // Ensure it's on top of everything
                .allowsHitTesting(true) // Allow interaction
            }
        }
        .alert("Reset Everything?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                showingPlaylistInput = true
            }
        } message: {
            Text("This will clear all your liked songs and start fresh with a new playlist. This action cannot be undone.")
        }
        .sheet(isPresented: $showingPlaylistInput) {
            if !isResetting {
                PlaylistInputSheet(newPlaylistID: $newPlaylistID) { playlistID in
                    if let playlistID = playlistID {
                        Task {
                            await performReset(with: playlistID)
                        }
                    }
                }
            }
        }
    }

    private func saveLikedToPlaylist() {
        let trackIDs = store.liked.compactMap { $0.spotifyID }
        print("Saving these to playlist:", trackIDs)
        // TODO!!!!: hook into backend/Spotify API to actually save
    }
    
    @MainActor
    private func performReset(with playlistID: String) async {
        // Dismiss the sheet first
        showingPlaylistInput = false
        
        // Small delay to ensure sheet is dismissed
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Show loading screen
        isResetting = true
        
        do {
            // Update playlist ID in UserDefaults
            UserDefaults.standard.set(playlistID, forKey: "currentPlaylistID")
            
            // Reset local state
            store.resetEverything()
            store.updatePlaylistID(playlistID)
            
            // Use the GET endpoint to load new data (this will work perfectly)
            await store.loadFromBackend()
            
            // Dismiss the liked songs view
            dismiss()
        } catch {
            // Handle error if needed
        }
        
        isResetting = false
    }
}

struct PlaylistInputSheet: View {
    @Binding var newPlaylistID: String
    let onComplete: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Enter New Playlist")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Paste a Spotify playlist URL or ID to start fresh")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist URL or ID")
                        .font(.headline)
                    
                    TextField("https://open.spotify.com/playlist/...", text: $newPlaylistID)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button {
                        if let playlistID = extractPlaylistID(from: newPlaylistID) {
                            onComplete(playlistID)
                        } else {
                            // Show error or handle invalid input
                        }
                    } label: {
                        Text("Start Fresh")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.blue)
                            )
                    }
                    .disabled(newPlaylistID.isEmpty)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Reset Playlist")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct LikedSongRow: View {
    let song: Song
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: song.artworkURL) { img in
                img.resizable().scaledToFill()
            } placeholder: { 
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                Text(song.artistDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .font(.title3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
func simpleGetUrlRequest(url: String, completion: @escaping (String?) -> Void) {
    guard let url = URL(string: url) else {
        print("❌ Invalid URL string:", url)
        completion(nil)
        return
    }

    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print("❌ Request failed:", error.localizedDescription)
            completion(nil)
            return
        }

        guard let data = data,
              let text = String(data: data, encoding: .utf8) else {
            completion(nil)
            return
        }

        completion(text)  // return to caller
    }
    .resume()
}

struct Network {
    static let shared: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60      // per request handshake / data
        cfg.timeoutIntervalForResource = 300    // entire transfer (5 minutes for AI processing)
        cfg.waitsForConnectivity = true         // cellular / wifi recoveries
        return URLSession(configuration: cfg)
    }()
    
    static let imageSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30      // 30 seconds for images
        cfg.timeoutIntervalForResource = 60     // 1 minute total for images
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()
}

@MainActor
func fetchSongs(for playlistURL: String) async throws -> [Song] {
    print("🌐 Fetching songs for playlist: \(playlistURL)")
    let comps = URLComponents(string: "http://127.0.0.1:5000/link/" + playlistURL)!

    var req = URLRequest(url: comps.url!)
    req.httpMethod = "GET"
    // Remove conflicting timeout - let URLSession handle it
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Spinder-iOS/1.0", forHTTPHeaderField: "User-Agent")

    let (data, resp) = try await Network.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        print("❌ Server error: \(statusCode)")
        throw URLError(.badServerResponse, userInfo: [
            NSLocalizedDescriptionKey: "Server returned status code: \(statusCode)"
        ])
    }

    // Debug: Print raw response
    if let jsonString = String(data: data, encoding: .utf8) {
        print("📥 Raw response (first 500 chars): \(String(jsonString.prefix(500)))")
    }

    // Decode JSON into array of Song
    let decoder = JSONDecoder()
    do {
        let songs = try decoder.decode([Song].self, from: data)
        print("✅ Successfully decoded \(songs.count) songs")
        return songs
    } catch {
        print("❌ Decoding error: \(error)")
        print("❌ Error details: \(error.localizedDescription)")
        throw error
    }
}

@MainActor
func clearBackendDatabase() async throws {
    let url = URL(string: "http://127.0.0.1:5000/clear")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Spinder-iOS/1.0", forHTTPHeaderField: "User-Agent")
    
    let (_, resp) = try await Network.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        throw URLError(.badServerResponse, userInfo: [
            NSLocalizedDescriptionKey: "Failed to clear database. Status: \(statusCode)"
        ])
    }
    
    print("✅ Successfully cleared backend database")
}

@MainActor
func postLikedSongsAndGetRecommendations(_ likedSongs: [Song]) async throws -> [Song] {
    let url = URL(string: "http://127.0.0.1:5000/songids")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Spinder-iOS/1.0", forHTTPHeaderField: "User-Agent")
    
    // Filter out songs with missing IDs and validate Spotify IDs
    let spotifyIDs = likedSongs
        .filter { !$0.spotifyID.hasPrefix("missing_id_") }
        .filter { $0.spotifyID.count == 22 && $0.spotifyID.allSatisfy { $0.isLetter || $0.isNumber } }
        .map { $0.spotifyID }
    
    // Only send if we have valid Spotify IDs
    guard !spotifyIDs.isEmpty else {
        print("⚠️ No valid Spotify IDs to send")
        return []
    }
    
    // Debug: Print what we're sending
    print("📤 Sending \(spotifyIDs.count) Spotify IDs to backend:", spotifyIDs)
    
    let encoder = JSONEncoder()
    req.httpBody = try encoder.encode(spotifyIDs)
    
    // Debug: Print the actual JSON being sent
    if let body = req.httpBody, let jsonString = String(data: body, encoding: .utf8) {
        print("📤 JSON body:", jsonString)
    }
    
    let (data, resp) = try await Network.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        throw URLError(.badServerResponse, userInfo: [
            NSLocalizedDescriptionKey: "Failed to send liked songs. Status: \(statusCode)"
        ])
    }
    
    // Decode the new recommendations
    let decoder = JSONDecoder()
    do {
        let songs = try decoder.decode([Song].self, from: data)
        
        // Debug: Check first few songs for image URLs
        for (index, song) in songs.prefix(3).enumerated() {
            print("🎵 Song \(index + 1): \(song.name)")
            print("   Image URL: \(song.imageURL)")
            print("   Artwork URL: \(song.artworkURL?.absoluteString ?? "nil")")
        }
        
        return songs
    } catch {
        throw error
    }
}



#Preview {
    SongSwipeHome()
}
