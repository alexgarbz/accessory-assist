import SwiftUI

/// Catalogue update status.
///
/// The screen someone opens when a price looks wrong. It answers, in order:
/// what is loaded, where it came from, when it last changed, whether the last
/// attempt worked, and — if a publish was rejected — exactly which rules it
/// broke, so the content owner can be told something specific.
struct CatalogueStatusView: View {
    @EnvironmentObject private var catalogue: CatalogueService

    private var snapshot: CatalogueSnapshot? { catalogue.snapshot }

    var body: some View {
        List {
            stateSection
            contentSection
            timingSection

            if !catalogue.lastValidationIssues.isEmpty {
                validationSection
            }

            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Catalogue Status")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await catalogue.refreshAndWait(force: true) }
    }

    // MARK: - State

    private var stateSection: some View {
        Section {
            switch stateTone {
            case .critical:
                StatusBanner(
                    title: "Catalogue Unavailable",
                    message: catalogue.lastError?.localizedDescription
                        ?? "No catalogue is loaded on this device.",
                    tone: .critical
                )
                .listRowBackground(Palette.canvas)
            case .warning:
                StatusBanner(
                    title: catalogue.isOffline ? "Using Offline Data" : "Last Update Failed",
                    message: catalogue.lastError?.localizedDescription
                        ?? "Showing the last catalogue that passed validation.",
                    tone: .warning
                )
                .listRowBackground(Palette.canvas)
            case .info:
                StatusBanner(
                    title: "Catalogue Up To Date",
                    message: outcomeMessage,
                    tone: .info,
                    systemImage: "checkmark.circle"
                )
                .listRowBackground(Palette.canvas)
            }
        }
    }

    private enum StateTone { case info, warning, critical }

    private var stateTone: StateTone {
        if snapshot == nil { return .critical }
        if catalogue.lastError != nil || snapshot?.isSeed == true { return .warning }
        return .info
    }

    private var outcomeMessage: String {
        switch catalogue.lastOutcome {
        case .updated(let from, let to):
            return from == 0
                ? "Downloaded catalogue version \(to)."
                : "Updated from version \(from) to \(to)."
        case .upToDate:
            return "The published version matches what is on this device."
        case .failed, .none:
            return "Loaded from this device's cache."
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        Section("Loaded Content") {
            DetailRow(label: "Source", value: catalogue.source.displayName)
            DetailRow(label: "Branch", value: catalogue.source.shortLabel, isMonospaced: true)
            if let snapshot {
                DetailRow(label: "Catalogue version", value: "\(snapshot.version.catalogueVersion)")
                DetailRow(label: "Environment", value: snapshot.catalogue.environment)
                DetailRow(label: "Products", value: "\(snapshot.sellableProducts.count) active of \(snapshot.catalogue.products.count)")
                DetailRow(label: "Bundles", value: "\(snapshot.activeBundles.count)")
                DetailRow(label: "Announcements", value: "\(snapshot.liveAnnouncements().count) live")
                if snapshot.isSeed {
                    DetailRow(label: "Origin", value: "Bundled with app", valueColor: Palette.warning)
                }
                if let notes = snapshot.version.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Publish notes")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textTertiary)
                        Text(notes)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            } else {
                Text("No catalogue loaded.")
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Timing

    private var timingSection: some View {
        Section("Timing") {
            DetailRow(label: "Last updated", value: Format.lastUpdated(catalogue.lastSuccessfulUpdate))
            DetailRow(
                label: "Last checked",
                value: catalogue.lastChecked.map { Format.lastUpdated($0) } ?? "Not checked yet"
            )
            if let published = snapshot?.version.publishedAt {
                DetailRow(label: "Published", value: Format.timestamp(published))
            }
            DetailRow(label: "Cache size", value: catalogue.cacheSizeDescription())
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Validation

    private var validationSection: some View {
        Section {
            ForEach(catalogue.lastValidationIssues) { issue in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        StatusPill(
                            text: issue.severity == .error ? "Error" : "Warning",
                            tone: issue.severity == .error ? .critical : .warning
                        )
                        Text(issue.path)
                            .font(TypeScale.mono)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                    Text(issue.message)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xxs)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Validation")
        } footer: {
            Text("Content that fails validation is rejected before it can replace the working catalogue on this device.")
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                Haptics.impact()
                catalogue.refresh(force: true)
            } label: {
                HStack {
                    Text(catalogue.isRefreshing ? "Refreshing…" : "Refresh Catalogue")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    if catalogue.isRefreshing { ProgressView() }
                }
                .frame(minHeight: TouchTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(catalogue.isRefreshing)
        }
        .listRowBackground(Palette.surface)
    }
}
