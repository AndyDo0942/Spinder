import SwiftUI

// MARK: - Backdrop & Dots
private struct DreamyBackdrop: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Circle().fill(Palette.aura1).frame(width: 320, height: 320)
                .blur(radius: 120).offset(x: -140, y: -240)
            Circle().fill(Palette.aura2).frame(width: 260, height: 260)
                .blur(radius: 120).offset(x: 160, y: 260)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Palette.grad :
                          LinearGradient(colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(width: i == index ? 12 : 8, height: i == index ? 12 : 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Icon helpers
private struct IconBadge: View {
    let systemName: String
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Palette.grad, lineWidth: 1))
                .frame(width: size + 14, height: size + 14)
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.grad)
        }
    }
}

private struct HeroIcon: View {
    let systemName: String
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial).frame(width: 72, height: 72)
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.grad)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Steps row
private struct StepRow: View {
    let number: Int
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, size: 18)
            HStack(spacing: 6) {
                Text("\(number).").font(.subheadline.bold()).foregroundStyle(.secondary)
                Text(title).font(.headline).foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Import sheet (placeholder wiring)
struct PlaylistLinkOnboarding: View {
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let onImported: ([Song]) -> Void

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Bring Your Playlist").font(.title.bold()).gradientText()
                Text("Paste a Spotify playlist link to seed recommendations.")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary)

                TextField("https://open.spotify.com/playlist/...", text: $input)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.grad.opacity(0.6), lineWidth: 1))
                    )
                    .foregroundColor(.gray)

                if let error { Text(error).font(.footnote).foregroundStyle(.red) }

                Button (action:{}){
                    // For now, just dismiss and let Home fetc from backend
                    onImported([])
                    dismiss()
                } label: {
                    Text("Use This Playlist").bold().foregroundStyle(.black)
                }
                .buttonStyle(GlassGradientButtonStyle())

                Button("Skip for now") { dismiss() }.foregroundStyle(.secondary)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}

// MARK: - Onboarding flow
struct DreamOnboarding: View {
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var page = 0
    @State private var showPlaylistSheet = false

    var body: some View {
        ZStack {
            DreamyBackdrop()
            
            VStack(spacing: 12) {
                // Header: show wordmark only after first page
                

                TabView(selection: $page) {
                    // 1) Intro — centered wordmark
                    VStack(spacing: 14) {
                        Spacer()
                        Text("Welcome to the sound of serendipity.")
                            .padding(.top,60)
                            .font(.title3).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            
                        Spacer()
                    }
                    .tag(0)

                    // 2) Problem
                    VStack(spacing: 16) {
                        HeroIcon(systemName: "repeat.circle")
                        Text("Stale playlists?").font(.title.bold()).foregroundStyle(.primary)
                        Text("Tired of looping the same songs? Craving something fresh without endless scrolling?")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)
                    }
                    .tag(1)

                    // 3) Solution + slogan
                    VStack(spacing: 14) {
                        HeroIcon(systemName: "wand.and.stars")
                        Text("Meet your music matchmaker.")
                            .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center).padding(.horizontal, 20).font(.title.bold())
                        Text("Swipe to discover. Like what you love. Skip what you don’t.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Text("Swipe into your next obsession ✨").font(.headline).gradientText()
                    }
                    .tag(2)

                    // 4) How it works
                    VStack(spacing: 16) {
                        HeroIcon(systemName: "slider.horizontal.3")
                        Text("How it works").font(.title.bold()).foregroundStyle(.primary)
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                IconBadge(systemName: "hand.point.right.fill", size: 18)
                                Text("Swipe right for love, left to skip.").foregroundStyle(.secondary)
                                Spacer()
                            }
                            HStack(spacing: 12) {
                                IconBadge(systemName: "sparkles", size: 18)
                                Text("We learn from every move to build your Taste Profile.").foregroundStyle(.secondary)
                                Spacer()
                            }
                            HStack(spacing: 12) {
                                IconBadge(systemName: "music.note.list", size: 18)
                                Text("Fresh tracks arrive—tailored to you.").foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    .tag(3)


                    // 5) CTA
                    VStack(spacing: 16) {
                        HeroIcon(systemName: "link.badge.plus")
                            .padding(.top,250   )
                        Text("Ready to start?").font(.title.bold()).foregroundStyle(.primary)
                        Text("Kick things off by importing a playlist. We’ll personalize your first deck from it.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 28)

                        Button {
                            showPlaylistSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Text("Import Playlist").bold()
                            }
                            .foregroundStyle(.black)
                        }
                        .buttonStyle(GlassGradientButtonStyle())
                        .padding(.top, 4)

                        Button("Skip for now") { didOnboard = true }
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                    }
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                PageDots(count: 5, index: page).padding(.bottom, 8)
            }
            .padding(.horizontal, 18)
            .overlay {
                GeometryReader { proxy in
                    // positions for intro vs. header
                    let centerY = proxy.size.height * 0.28
                    let headerY: CGFloat = 12

                    HStack(spacing: -20) {
                        Text("Spinder")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .gradientText()

                        Image("SpinderLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120) // adjust to balance text
                    }
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .padding(.top,200)
                        .gradientText()
                        .scaleEffect(page == 0 ? 1.0 : 0.57, anchor: .center) // shrink on page 1+
                        .position(
                            x: proxy.size.width / 2,
                            y: page == 0 ? centerY : headerY + 20              // slide up
                        )
                        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: page)
                        .allowsHitTesting(false)
                }
            }

        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistLinkOnboarding { _ in didOnboard = true }
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationCornerRadius(28)
                .presentationDragIndicator(.hidden)
        }
    }
}
#Preview { DreamOnboarding() }
