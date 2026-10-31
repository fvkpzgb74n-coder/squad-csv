import SwiftUI

/// Explains Lineup Pro and lets the user buy or restore it.
struct ProPaywallView: View {
    /// Why the paywall appeared, e.g. "Free version is limited to 3 lineups."
    var reason: String? = nil

    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.yellow.gradient)
                        Text("Lineup Pro")
                            .font(.largeTitle.weight(.heavy))
                        if let reason {
                            Text(reason)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(
                            icon: "infinity",
                            color: .blue,
                            title: "Unlimited players & lineups",
                            detail: "Free is limited to \(ProStore.freePlayerLimit) players and \(ProStore.freeLineupLimit) lineups."
                        )
                        FeatureRow(
                            icon: "stopwatch.fill",
                            color: .green,
                            title: "Match Day mode",
                            detail: "Live match clock, score, and one-tap substitutions from the bench."
                        )
                        FeatureRow(
                            icon: "chart.bar.fill",
                            color: .orange,
                            title: "Fair playing time",
                            detail: "See every player's minutes as the game goes on, so everyone gets a fair go."
                        )
                    }
                    .padding(20)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                    if pro.isPro {
                        Label("Pro is unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        purchaseButtons
                    }

                    if pro.canUseTestUnlock {
                        testModeSection
                    }
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if pro.isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(
                pro.errorMessage ?? "",
                isPresented: Binding(
                    get: { pro.errorMessage != nil },
                    set: { if !$0 { pro.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            }
            .task {
                await pro.loadProduct()
            }
        }
    }

    private var purchaseButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await pro.purchase() }
            } label: {
                Text(pro.product.map { "Unlock Pro for \($0.displayPrice)" } ?? "Unlock Pro")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pro.product == nil || pro.isWorking)

            Text("One-off payment. No subscription.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if pro.product == nil && pro.hasLoadedProduct {
                Text("Pro can't be bought here yet. It becomes available once the app is set up in App Store Connect.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Restore Purchase") {
                Task { await pro.restore() }
            }
            .disabled(pro.isWorking)
        }
    }

    private var testModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Test mode: unlock Pro for free",
                isOn: Binding(get: { pro.testUnlock }, set: { pro.setTestUnlock($0) })
            )
            Text("Only shown while testing. Customers who download the app from the App Store won't see this.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Small "PRO" tag shown next to locked features.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.yellow, in: Capsule())
    }
}

#Preview {
    ProPaywallView(reason: "The free version is limited to 3 lineups.")
        .environment(ProStore())
}
