import AppKit
import Foundation
import GhosttyKit
import Observation

@MainActor
@Observable
final class MultiWorktreeSplitContainer {
  let runtime: GhosttyRuntime
  let primaryWorktree: Worktree
  private var _tree: SplitTree<GhosttySurfaceView>
  private var _surfaces: [UUID: GhosttySurfaceView] = [:]
  private var _surfaceWorktrees: [UUID: Worktree] = [:]
  private var _focusedSurfaceID: UUID?

  var tree: SplitTree<GhosttySurfaceView> { _tree }
  var surfaces: [UUID: GhosttySurfaceView] { _surfaces }
  var isEmpty: Bool { _tree.isEmpty }

  init(runtime: GhosttyRuntime, primaryWorktree: Worktree) {
    self.runtime = runtime
    self.primaryWorktree = primaryWorktree
    self._tree = SplitTree()

    let initialSurface = createSurface(for: primaryWorktree)
    _surfaces[initialSurface.id] = initialSurface
    _surfaceWorktrees[initialSurface.id] = primaryWorktree
    _tree = SplitTree(view: initialSurface)
    _focusedSurfaceID = initialSurface.id
  }

  func createSurface(for worktree: Worktree) -> GhosttySurfaceView {
    let view = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: worktree.workingDirectory,
      initialInput: nil
    )

    view.bridge.onSplitAction = { [weak self, weak view] action in
      guard let self, let view else { return false }
      return self.performSplitAction(action, for: view.id)
    }
    view.bridge.onCloseRequest = { [weak self, weak view] processAlive in
      guard let self, let view else { return }
      self.handleCloseRequest(for: view)
    }
    view.onFocusChange = { [weak self, weak view] focused in
      guard let self, let view, focused else { return }
      self._focusedSurfaceID = view.id
    }

    _surfaceWorktrees[view.id] = worktree
    return view
  }

  func insertSurface(for worktree: Worktree, at destinationID: UUID, zone: TerminalSplitTreeView.DropZone) -> Bool {
    guard let destinationSurface = _surfaces[destinationID] else { return false }

    let newSurface = createSurface(for: worktree)
    _surfaces[newSurface.id] = newSurface

    do {
      let newTree = try _tree.inserting(
        view: newSurface,
        at: destinationSurface,
        direction: mapDropZone(zone)
      )
      _tree = newTree
      focusSurface(newSurface.id)
      return true
    } catch {
      newSurface.closeSurface()
      _surfaces.removeValue(forKey: newSurface.id)
      _surfaceWorktrees.removeValue(forKey: newSurface.id)
      return false
    }
  }

  func performSplitOperation(_ operation: TerminalSplitTreeView.Operation) {
    switch operation {
    case .resize(let node, let ratio):
      let resizedNode = node.resizing(to: ratio)
      try? _tree = _tree.replacing(node: node, with: resizedNode)

    case .drop(let payloadId, let destinationId, let zone):
      guard let payload = _surfaces[payloadId],
        let destination = _surfaces[destinationId],
        payload !== destination
      else { return }
      guard let sourceNode = _tree.root?.node(view: payload) else { return }
      let treeWithoutSource = _tree.removing(sourceNode)
      if treeWithoutSource.isEmpty { return }
      try? _tree = treeWithoutSource.inserting(
        view: payload,
        at: destination,
        direction: mapDropZone(zone)
      )
      focusSurface(payloadId)

    case .equalize:
      _tree = _tree.equalized()
    }
  }

  func performSplitAction(_ action: GhosttySplitAction, for surfaceID: UUID) -> Bool {
    guard let node = _tree.find(id: surfaceID) else { return false }

    switch action {
    case .newSplit(let direction):
      guard let worktree = _surfaceWorktrees[surfaceID],
        let sourceSurface = _surfaces[surfaceID]
      else { return false }

      let newSurface = createSurface(for: worktree)
      _surfaces[newSurface.id] = newSurface

      do {
        _tree = try _tree.inserting(
          view: newSurface,
          at: sourceSurface,
          direction: mapSplitDirection(direction)
        )
        focusSurface(newSurface.id)
        return true
      } catch {
        newSurface.closeSurface()
        _surfaces.removeValue(forKey: newSurface.id)
        _surfaceWorktrees.removeValue(forKey: newSurface.id)
        return false
      }

    case .gotoSplit(let direction):
      let focusDirection = mapFocusDirection(direction)
      if let nextSurface = _tree.focusTarget(for: focusDirection, from: node) {
        focusSurface(nextSurface.id)
        return true
      }
      return false

    case .resizeSplit(let direction, let amount):
      let spatialDirection = mapResizeDirection(direction)
      try? _tree = _tree.resizing(
        node: node,
        by: amount,
        in: spatialDirection,
        with: CGRect(origin: .zero, size: _tree.viewBounds())
      )
      return true

    case .equalizeSplits:
      _tree = _tree.equalized()
      return true

    case .toggleSplitZoom:
      guard _tree.isSplit else { return false }
      _tree = _tree.settingZoomed(_tree.zoomed == node ? nil : node)
      return true
    }
  }

  func worktree(for surfaceID: UUID) -> Worktree? {
    _surfaceWorktrees[surfaceID]
  }

  private func focusSurface(_ id: UUID) {
    _focusedSurfaceID = id
    if let surface = _surfaces[id] {
      surface.requestFocus()
    }
  }

  private func handleCloseRequest(for view: GhosttySurfaceView) {
    guard _surfaces[view.id] != nil else { return }
    guard let node = _tree.find(id: view.id) else {
      view.closeSurface()
      _surfaces.removeValue(forKey: view.id)
      _surfaceWorktrees.removeValue(forKey: view.id)
      return
    }
    let newTree = _tree.removing(node)
    view.closeSurface()
    _surfaces.removeValue(forKey: view.id)
    _surfaceWorktrees.removeValue(forKey: view.id)

    if newTree.isEmpty {
      // Signal to close container - caller should check isEmpty
      _tree = newTree
      return
    }
    _tree = newTree
    if _focusedSurfaceID == view.id {
      _focusedSurfaceID = newTree.root?.leftmostLeaf()?.id
    }
  }

  private func mapDropZone(_ zone: TerminalSplitTreeView.DropZone) -> SplitTree<GhosttySurfaceView>.NewDirection {
    switch zone {
    case .top: return .top
    case .bottom: return .down
    case .left: return .left
    case .right: return .right
    }
  }

  private func mapSplitDirection(_ direction: GhosttySplitAction.NewDirection) -> SplitTree<GhosttySurfaceView>.NewDirection {
    switch direction {
    case .left: return .left
    case .right: return .right
    case .top: return .top
    case .down: return .down
    }
  }

  private func mapFocusDirection(_ direction: GhosttySplitAction.FocusDirection) -> SplitTree<GhosttySurfaceView>.FocusDirection {
    switch direction {
    case .previous: return .previous
    case .next: return .next
    case .left: return .spatial(.left)
    case .right: return .spatial(.right)
    case .top: return .spatial(.top)
    case .down: return .spatial(.down)
    }
  }

  private func mapResizeDirection(_ direction: GhosttySplitAction.ResizeDirection) -> SplitTree<GhosttySurfaceView>.SpatialDirection {
    switch direction {
    case .left: return .left
    case .right: return .right
    case .top: return .top
    case .down: return .down
    }
  }

  func closeAll() {
    for surface in _surfaces.values {
      surface.closeSurface()
    }
    _surfaces.removeAll()
    _surfaceWorktrees.removeAll()
    _tree = SplitTree()
  }
}
