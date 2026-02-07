import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MultiWorktreeSplitView: View {
  @Bindable var container: MultiWorktreeSplitContainer
  let allWorktrees: [Worktree]
  let onWorktreeDrop: (Worktree.ID, UUID, TerminalSplitTreeView.DropZone) -> Void
  let onClose: () -> Void

  var body: some View {
    if let node = container.tree.zoomed ?? container.tree.root {
      SubtreeView(
        node: node,
        isRoot: node == container.tree.root,
        container: container,
        allWorktrees: allWorktrees,
        onWorktreeDrop: onWorktreeDrop
      )
      .id(node.structuralIdentity)
      .onChange(of: container.isEmpty) { _, isEmpty in
        if isEmpty {
          onClose()
        }
      }
    }
  }

  struct SubtreeView: View {
    let node: SplitTree<GhosttySurfaceView>.Node
    var isRoot: Bool = false
    @Bindable var container: MultiWorktreeSplitContainer
    let allWorktrees: [Worktree]
    let onWorktreeDrop: (Worktree.ID, UUID, TerminalSplitTreeView.DropZone) -> Void

    var body: some View {
      switch node {
      case .leaf(let leafView):
        LeafView(
          surfaceView: leafView,
          isSplit: !isRoot,
          container: container,
          allWorktrees: allWorktrees,
          onWorktreeDrop: onWorktreeDrop
        )
      case .split(let split):
        let splitViewDirection: SplitView<SubtreeView, SubtreeView>.Direction =
          switch split.direction {
          case .horizontal: .horizontal
          case .vertical: .vertical
          }
        SplitView(
          splitViewDirection,
          .init(
            get: { CGFloat(split.ratio) },
            set: { container.performSplitOperation(.resize(node: node, ratio: Double($0))) }
          ),
          dividerColor: .secondary,
          resizeIncrements: .init(width: 1, height: 1),
          left: {
            SubtreeView(
              node: split.left,
              container: container,
              allWorktrees: allWorktrees,
              onWorktreeDrop: onWorktreeDrop
            )
          },
          right: {
            SubtreeView(
              node: split.right,
              container: container,
              allWorktrees: allWorktrees,
              onWorktreeDrop: onWorktreeDrop
            )
          },
          onEqualize: {
            container.performSplitOperation(.equalize)
          }
        )
      }
    }
  }

  struct LeafView: View {
    let surfaceView: GhosttySurfaceView
    let isSplit: Bool
    @Bindable var container: MultiWorktreeSplitContainer
    let allWorktrees: [Worktree]
    let onWorktreeDrop: (Worktree.ID, UUID, TerminalSplitTreeView.DropZone) -> Void

    @State private var dropState: DropState = .idle

    var body: some View {
      GeometryReader { geometry in
        GhosttyTerminalView(surfaceView: surfaceView)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .top) {
            GhosttySurfaceProgressOverlay(state: surfaceView.bridge.state)
          }
          .overlay(alignment: .topTrailing) {
            if surfaceView.bridge.state.searchNeedle != nil {
              GhosttySurfaceSearchOverlay(surfaceView: surfaceView)
            }
          }
          .overlay(alignment: .topLeading) {
            WorktreeIndicator(worktree: worktree)
          }
          .overlay(alignment: .top) {
            if isSplit {
              DragHandle(surfaceView: surfaceView)
            }
          }
          .background {
            Color.clear
              .contentShape(.rect)
              .onDrop(
                of: [
                  TerminalSplitTreeView.dragType,
                  Self.worktreeDragType,
                ],
                delegate: MultiDropDelegate(
                  dropState: $dropState,
                  viewSize: geometry.size,
                  destinationId: surfaceView.id,
                  onWorktreeDrop: onWorktreeDrop,
                  onSurfaceDrop: { payloadId, destinationId, zone in
                    container.performSplitOperation(
                      .drop(payloadId: payloadId, destinationId: destinationId, zone: zone))
                  }
                )
              )
          }
          .overlay {
            if case .dropping(let zone) = dropState {
              DropOverlayView(zone: zone, size: geometry.size)
                .allowsHitTesting(false)
            }
          }
      }
    }

    private var worktree: Worktree? {
      container.worktree(for: surfaceView.id)
    }

    private static let worktreeDragType = UTType(exportedAs: "sh.supacode.worktreeId")
  }

  struct WorktreeIndicator: View {
    let worktree: Worktree?

    var body: some View {
      if let worktree {
        HStack(spacing: 4) {
          Text(worktree.name)
            .font(.system(.caption2, weight: .medium))
            .foregroundStyle(.primary)
          Image(systemName: "chevron.right")
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
          Text(worktree.repositoryRootURL.lastPathComponent)
            .font(.system(.caption2))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(.regularMaterial)
        )
        .padding(4)
      }
    }
  }

  struct DragHandle: View {
    let surfaceView: GhosttySurfaceView
    private let handleHeight: CGFloat = 10
    @State private var isHovering = false

    var body: some View {
      Rectangle()
        .fill(Color.primary.opacity(isHovering ? 0.12 : 0))
        .frame(maxWidth: .infinity)
        .frame(height: handleHeight)
        .overlay {
          if isHovering {
            Image(systemName: "ellipsis")
              .font(.system(.callout, weight: .semibold))
              .foregroundStyle(.primary.opacity(0.5))
              .accessibilityHidden(true)
          }
        }
        .contentShape(.rect)
        .onHover { hovering in
          guard hovering != isHovering else { return }
          isHovering = hovering
          if hovering {
            NSCursor.openHand.push()
          } else {
            NSCursor.pop()
          }
        }
        .onDisappear {
          if isHovering {
            isHovering = false
            NSCursor.pop()
          }
        }
        .onDrag {
          let provider = NSItemProvider()
          let data = surfaceView.id.uuidString.data(using: .utf8) ?? Data()
          provider.registerDataRepresentation(
            forTypeIdentifier: TerminalSplitTreeView.dragType.identifier,
            visibility: .all
          ) { completion in
            completion(data, nil)
            return nil
          }
          return provider
        }
    }
  }

  enum DropState: Equatable {
    case idle
    case dropping(TerminalSplitTreeView.DropZone)
  }

  struct MultiDropDelegate: DropDelegate {
    @Binding var dropState: DropState
    let viewSize: CGSize
    let destinationId: UUID
    let onWorktreeDrop: (Worktree.ID, UUID, TerminalSplitTreeView.DropZone) -> Void
    let onSurfaceDrop: (UUID, UUID, TerminalSplitTreeView.DropZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
      info.hasItemsConforming(to: [
        TerminalSplitTreeView.dragType,
        UTType(exportedAs: "sh.supacode.worktreeId"),
      ])
    }

    func dropEntered(info: DropInfo) {
      dropState = .dropping(.calculate(at: info.location, in: viewSize))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
      dropState = .dropping(.calculate(at: info.location, in: viewSize))
      return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
      dropState = .idle
    }

    func performDrop(info: DropInfo) -> Bool {
      let zone = TerminalSplitTreeView.DropZone.calculate(at: info.location, in: viewSize)
      dropState = .idle

      // First try to handle worktree drop
      let worktreeType = UTType(exportedAs: "sh.supacode.worktreeId")
      let providers = info.itemProviders(for: [worktreeType])
      if let provider = providers.first {
        provider.loadDataRepresentation(forTypeIdentifier: worktreeType.identifier) { data, _ in
          guard let data,
            let raw = String(data: data, encoding: .utf8)
          else { return }
          Task { @MainActor in
            onWorktreeDrop(raw, destinationId, zone)
          }
        }
        return true
      }

      // Otherwise handle surface drop
      let surfaceProviders = info.itemProviders(for: [TerminalSplitTreeView.dragType])
      guard let provider = surfaceProviders.first else { return false }
      provider.loadDataRepresentation(
        forTypeIdentifier: TerminalSplitTreeView.dragType.identifier
      ) { data, _ in
        guard let data,
          let raw = String(data: data, encoding: .utf8),
          let payloadId = UUID(uuidString: raw)
        else { return }
        Task { @MainActor in
          onSurfaceDrop(payloadId, destinationId, zone)
        }
      }
      return true
    }
  }

  struct DropOverlayView: View {
    let zone: TerminalSplitTreeView.DropZone
    let size: CGSize

    var body: some View {
      let overlayColor = Color.accentColor.opacity(0.3)

      switch zone {
      case .top:
        VStack(spacing: 0) {
          Rectangle()
            .fill(overlayColor)
            .frame(height: size.height / 2)
          Spacer()
        }
      case .bottom:
        VStack(spacing: 0) {
          Spacer()
          Rectangle()
            .fill(overlayColor)
            .frame(height: size.height / 2)
        }
      case .left:
        HStack(spacing: 0) {
          Rectangle()
            .fill(overlayColor)
            .frame(width: size.width / 2)
          Spacer()
        }
      case .right:
        HStack(spacing: 0) {
          Spacer()
          Rectangle()
            .fill(overlayColor)
            .frame(width: size.width / 2)
        }
      }
    }
  }
}
