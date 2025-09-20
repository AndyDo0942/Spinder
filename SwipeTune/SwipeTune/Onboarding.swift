import SwiftUI

// MARK: - Aesthetic (white base + dreamy purple accents)
private struct Palette {
    static let grad = LinearGradient(
        colors: [
            Color(hue: 0.76, saturation: 0.72, brightness: 0.88), // lavender
            Color(hue: 0.86, saturation: 0.60, brightness: 0.92), // pinkish violet
            Color(hue: 0.64, saturation: 0.55, brightness: 0.90)  // periwinkle
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let subtle = LinearGradient(
        colors: [
            Color.purple.opacity(0.28),
            Color.pink.opacity(0.18)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct DreamyBackdrop: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            // Soft blurred gradient auras (very subtle)
            Circle()
                .fill(Palette.subtle)
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: -140, y: -240)

            Circle()
                .fill(LinearGradient(colors: [Color.purple.opacity(0.22), Color.blue.opacity(0.18)],
                                     startPoint: .bottomLeading, endPoint: .topTrailing))
                .frame(width: 260, height: 260)
                .blur(radius: 120)
                .offset(x: 160, y: 260)
        }
    }
}

// MARK: - Dot indicator (current dot grows; gradient fill)
private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Palette.grad : LinearGradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.18)],
                                                                     startPoint: .top, endPoint: .bottom))
                    .frame(width: i == index ? 12 : 8, height: i == index ? 12 : 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
                    .shadow(color: (i == index ? Color.purple : .clear).opacity(0.18), radius: 6, x: 0, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}

// MARK: - 6-screen onboarding with logo motion + gradient type
struct DreamOnboarding: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var page = 0
    @State private var showPlaylistSheet = false

    // Logo animation
    @State private var logoAtTop = false
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            DreamyBackdrop()

            VStack(spacing: 16) {
                // Animated logo: fade in centered, then slide to top from page 1+
                Text("Spinder")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.grad) // gradient text
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    .opacity(logoOpacity)
                    .scaleEffect(logoAtTop ? 0.9 : 1.05)
                    .frame(maxWidth: .infinity)
                    .padding(.top, logoAtTop ? 8 : 64)
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: logoAtTop)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.7)) { logoOpacity = 1 }
                    }

                TabView(selection: $page) {
                    // 1) Intro (logo centered, gentle line)
                    VStack(spacing: 16) {
                        Spacer(minLength: 8)
                        Text("Welcome to the sound of serendipity.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                        Spacer()
                    }
                    .tag(0)

                    // 2) Problem: stale playlists
                    VStack(spacing: 16) {
                        Text("Stale playlists?")
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                        Text("Tired of looping the same songs?\nCraving something fresh without endless scrolling?")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                    }
                    .tag(1)

                    // 3) Solution + slogan (catchy)
                    VStack(spacing: 14) {
                        Text("Meet your music matchmaker.")
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                        Text("Swipe to discover. Like what you love. Skip what you don’t.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Text("Swipe into your next obsession ✨")
                            .font(.headline)
                            .foregroundStyle(Palette.grad)
                    }
                    .tag(2)

                    // 4) How it works (high-level)
                    VStack(spacing: 16) {
                        Text("How it works")
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                        Text("We learn your taste from every like and skip, then conjure fresh tracks you’ll actually vibe with.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .tag(3)

                    // 5) Overview steps
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The Flow")
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                            .padding(.top, 150)
                        StepRow(number: 1, title: "Upload your Spotify playlist")
                        StepRow(number: 2, title: "Swipe songs — right to like, left to skip")
                        StepRow(number: 3, title: "AI builds your Taste Profile")
                        StepRow(number: 4, title: "Discover new songs!")
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(4)

                    // 6) CTA screen → open import sheet
                    VStack(spacing: 16) {
                        Text("Ready to start?")
                            .font(.title.bold())
                            .foregroundStyle(.primary)

                        Text("Kick things off by importing a playlist.\nWe’ll personalize your first deck from it.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)

                        Button {
                            showPlaylistSheet = true
                        } label: {
                            Text("Import Playlist")
                                .font(.headline)
                                .bold()
                                .padding(.horizontal, 26).padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Palette.grad, lineWidth: 2)
                                )
                                .foregroundStyle(.black)
                                .shadow(color: .purple.opacity(0.18), radius: 16, x: 0, y: 8)
                        }
                        .padding(.top, 4)

                        Button("Skip for now") { didOnboard = true }
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        Spacer(minLength: 8)
                    }
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, newPage in
                    // Slide logo to the top from page 1 onward
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.88)) {
                        logoAtTop = newPage >= 1
                    }
                    // Auto-open import on last page
                    if newPage == 5 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showPlaylistSheet = true
                        }
                    }
                }

                PageDots(count: 6, index: page)
                    .padding(.bottom, 8)
            }
            .padding(.top, 20)
            .padding(.horizontal, 18)
        }
        .sheet(isPresented: $showPlaylistSheet) {
            // Reuse your existing import sheet from SwipeKit.swift
            PlaylistLinkOnboarding { importedSongs in
                // After successful import → mark onboarding done (ContentView will route to deck)
                didOnboard = true
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Step row with gradient index badge
private struct StepRow: View {
    let number: Int
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Palette.grad)
                    .frame(width: 34, height: 34)
                    .shadow(color: .purple.opacity(0.18), radius: 8, x: 0, y: 4)
                Text("\(number)")
                    .font(.headline).bold()
                    .foregroundStyle(.white)
            }
            Text(title)
                .foregroundStyle(.primary)
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview { DreamOnboarding() }
