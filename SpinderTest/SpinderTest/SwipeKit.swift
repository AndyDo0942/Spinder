import SwiftUI
import AVFoundation
import WebKit
import Combine

// MARK: - Model
struct Song: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let artists: [String]
    let artworkURL: URL?
    let previewURL: URL?           // unused for Spotify embed; keep for future Apple Music
    let spotifyID: String?         // used for the 30s embed

    var artistDisplay: String { artists.joined(separator: ", ") }
}

// MARK: - Backend DTO + Client
struct BackendSongDTO: Decodable {
    let name: String
    let artists: [String]
    let spotify_id: String
    let imageurl: String
}

enum BackendClient {
    // TODO: change base to your Flask host
    static let base = URL(string: "http://127.0.0.1:5000")!

    static func fetchRecommendedSongs() async throws -> [Song] {
        let url = base.appendingPathComponent("recommendations")
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode([BackendSongDTO].self, from: data)
        return decoded.map {
            Song(
                title: $0.name,
                artists: $0.artists,
                artworkURL: URL(string: $0.imageurl),
                previewURL: nil,
                spotifyID: $0.spotify_id
            )
        }
    }
}

// MARK: - Store
@MainActor
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

    func loadFromBackend() async {
        do {
            let songs = try await BackendClient.fetchRecommendedSongs()
            reset(with: songs)
        } catch {
            print("Fetch error:", error)
        }
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

import SwiftUI
import WebKit

struct SpotifyEmbedView: UIViewRepresentable {
    let trackID: String

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false

        wv.loadHTMLString(makeHTML(for: trackID), baseURL: nil)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(makeHTML(for: trackID), baseURL: nil)
    }

    private func makeHTML(for trackID: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
        </head>
        <body style="margin:0;background:transparent;">
            <div id="embed-iframe"></div>
            <script>
                window.onSpotifyIframeApiReady = (IFrameAPI) => {
                    const element = document.getElementById('embed-iframe');
                    const options = {
                        uri: 'spotify:track:\(trackID)'
                    };
                    const callback = (EmbedController) => {
                        // Try autoplay with mute workaround
                        EmbedController.setVolume(0); // start muted
                        EmbedController.play();

                        // Unmute after a short delay (500ms)
                        setTimeout(() => {
                            EmbedController.setVolume(1);
                        }, 500);
                    };
                    IFrameAPI.createController(element, options, callback);
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
                AsyncImage(url: song.artworkURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
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

// MARK: - Deck
struct SongSwipeDeck: View {
    @ObservedObject var store: SwipeStore

    @State private var currentTopID: String?

    var body: some View {
        ZStack {
            ForEach(Array(store.deck.enumerated()), id: \.element.id) { idx, song in
                SongCard(song: song) { like in
                    withAnimation { store.swipe(song, like: like) }
                }
                .padding(20)
                // make sure top card draws on TOP visually (optional but nice)
                .zIndex(Double(store.deck.count - idx))
                .scaleEffect(1 - (CGFloat(idx) * 0.02))
                .offset(y: CGFloat(idx) * 8)
            }

            if store.deck.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list").font(.largeTitle)
                    Text("You're all caught up!")
                    ProgressView().padding(4)
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
                .padding(.top, 200)
                .shadow(radius: 10)
            }
        }
        .onAppear {
            currentTopID = store.deck.first?.spotifyID
        }
        // whenever the top song changes (after a swipe), update the embed
        .onChange(of: store.deck.first?.id) { _, _ in
            currentTopID = store.deck.first?.spotifyID
        }
        // Embed for the top song
        .safeAreaInset(edge: .bottom) {
            if let id = currentTopID {
                SpotifyEmbedView(trackID: id)
                    .id(id)
                    .frame(height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 0)
            } else {
                Spacer(minLength: 1)
            }
        }
    }
}


// MARK: - Demo
enum DemoData {
    static let songs: [Song] = [
        Song(title: "Midnight City", artists: ["M83"], artworkURL: URL(string: "https://picsum.photos/seed/a/600/600"), previewURL: nil, spotifyID: "1Ukxccao1BlWrPhYkcXbwZ"),
        Song(title: "Blinding Lights", artists: ["The Weeknd"], artworkURL: URL(string: "https://picsum.photos/seed/b/600/600"), previewURL: nil, spotifyID: "5meVa5klVlJalupZTvv5XX"),
        Song(title: "Levitating", artists: ["Dua Lipa"], artworkURL: URL(string: "https://picsum.photos/seed/c/600/600"), previewURL: nil, spotifyID: "5meVa5klVlJalupZTvv5XX")
    ]
}

// MARK: - Home
struct SongSwipeHome: View {
    @StateObject private var store = SwipeStore(deck: DemoData.songs)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Gradient Title
                HStack(spacing: -5) {
                    Text("Spinder")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .gradientText()

                    Image("SpinderLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 65, height: 65) // adjust to balance text
                }
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .gradientText() // ✅ uses the extension that applies Palette.grad
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .padding(.top, 10)

                SongSwipeDeck(store: store)
                    .padding(.top,10)
                //check this code
            }
            .toolbar {
                NavigationLink {
                    LikedListView(liked: store.liked)
                } label: { Image(systemName: "heart") }
            }
        }
        .task {
            await store.loadFromBackend()   // pulls JSON from Flask when Home appears
        }
    }
}

struct LikedListView: View {
    let liked: [Song]

    var body: some View {
        List(liked) { s in
            HStack(spacing: 12) {
                AsyncImage(url: s.artworkURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading) {
                    Text(s.title).font(.headline)
                    Text(s.artistDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Liked")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    saveLikedToPlaylist()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Save to Spotify Playlist")
            }
        }
    }

    private func saveLikedToPlaylist() {
        let trackIDs = liked.compactMap { $0.spotifyID }
        print("Saving these to playlist:", trackIDs)
        // TODO!!!!: hook into backend/Spotify API to actually save
    }
}
func simpleGetUrlRequest(url: String)
    {
        let url = URL(string: url)!

        let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
            guard let data = data else { return }
            print("The response is : ",String(data: data, encoding: .utf8)!)
            //print(NSString(data: data, encoding: String.Encoding.utf8.rawValue) as Any)
        }
        task.resume()
    }
#Preview {
    SongSwipeHome()
}
