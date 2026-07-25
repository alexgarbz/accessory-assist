import SwiftUI

/// One SKU to be presented at the mPOS terminal.
///
/// A cart line of three units becomes three scan items, not one item with a
/// quantity: the position counter then matches the number of scans left to do,
/// and `subtitle` says which unit of the line is on screen.
struct ScanItem: Identifiable, Hashable {
    let id: String
    let sku: String
    let name: String
    let subtitle: String?

    init(id: String, sku: String, name: String, subtitle: String? = nil) {
        self.id = id
        self.sku = sku
        self.name = name
        self.subtitle = subtitle
    }

    init(product: Product, subtitle: String? = nil, idSuffix: String = "") {
        self.init(
            id: product.id + idSuffix,
            sku: product.sku,
            name: product.name,
            subtitle: subtitle
        )
    }
}

/// Full-screen barcode presentation for scanning at the mPOS terminal.
///
/// Everything here serves one goal: a scanner reads the screen first time.
/// White field, maximum brightness, auto-lock disabled, and controls large
/// enough to operate without looking away from the terminal.
struct ScanModeView: View {
    let items: [ScanItem]
    var startIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var brightness = ScreenBrightnessController()

    @State private var index: Int = 0

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            // Fixed white field — the barcode's quiet zone extends into it.
            Color.white.ignoresSafeArea()

            if items.isEmpty {
                EmptyStateView(
                    title: "Nothing to scan",
                    message: "Add an accessory to the cart, then start scan mode.",
                    systemImage: "barcode",
                    actionTitle: "Close",
                    action: { close() }
                )
            } else {
                VStack(spacing: 0) {
                    header

                    TabView(selection: $index) {
                        ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                            scanPage(for: item)
                                .tag(position)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(Motion.immediate, value: index)

                    controls
                }
            }
        }
        .preferredColorScheme(.light)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            index = min(max(startIndex, 0), max(items.count - 1, 0))
            brightness.beginScanMode(brightness: settings.scanBrightness)
        }
        .onDisappear {
            brightness.endScanMode()
        }
        .accessibilityAction(.escape) { close() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            Text("mPOS Scan")
                .font(TypeScale.label)
                .foregroundStyle(.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(1.5)

            Spacer()

            if items.count > 1 {
                Text("\(index + 1) of \(items.count)")
                    .font(TypeScale.label)
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.5))
                    .accessibilityLabel("Item \(index + 1) of \(items.count)")
            }

            Button {
                close()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "xmark")
                        .font(.system(size: IconSize.small, weight: .semibold))
                    Text("Exit")
                        .font(TypeScale.button)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: TouchTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit scan mode")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Page

    private func scanPage(for item: ScanItem) -> some View {
        VStack(spacing: isLandscape ? Spacing.m : Spacing.l) {
            Spacer(minLength: 0)

            BarcodePanel(sku: item.sku, height: isLandscape ? 140 : 210)
                .padding(.horizontal, Spacing.l)

            VStack(spacing: Spacing.xxs) {
                Text(item.name)
                    .font(TypeScale.scanTitle)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(TypeScale.secondary)
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .padding(.horizontal, Spacing.l)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), SKU \(Format.spokenSKU(item.sku))")
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Spacing.m) {
            stepButton(
                systemImage: "chevron.left",
                label: "Previous",
                isEnabled: index > 0
            ) {
                step(by: -1)
            }

            stepButton(
                systemImage: "chevron.right",
                label: "Next",
                isEnabled: index < items.count - 1
            ) {
                step(by: 1)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.m)
        .opacity(items.count > 1 ? 1 : 0)
        .allowsHitTesting(items.count > 1)
    }

    private func stepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if systemImage == "chevron.left" {
                    Image(systemName: systemImage)
                        .font(.system(size: IconSize.medium, weight: .semibold))
                }
                Text(label)
                    .font(TypeScale.button)
                if systemImage == "chevron.right" {
                    Image(systemName: systemImage)
                        .font(.system(size: IconSize.medium, weight: .semibold))
                }
            }
            .foregroundStyle(isEnabled ? .black : .black.opacity(0.25))
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? TouchTarget.comfortable : TouchTarget.scanControl)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.black.opacity(isEnabled ? 0.06 : 0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func step(by delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        withAnimation(Motion.immediate) { index = next }
        Haptics.selection()
    }

    private func close() {
        brightness.endScanMode()
        dismiss()
    }
}
