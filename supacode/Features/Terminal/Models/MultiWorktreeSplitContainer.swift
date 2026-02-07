import AppKit
import Foundation
import GhosttyKit
import Observation

@MainActor
@Observable
final class MultiWorktreeSplitContainer {
  let runtime: GhosttyRuntime
  let primaryWorktree: Worktree
  private weak var terminalManager: WorktreeTerminalManager?
  private var _tree: SplitTree<GhosttySurfaceView>
  private var _surfaces: [UUID: GhosttySurfaceView] = [:]
  private var _surfaceWorktrees: [UUID: Worktree] = [:]
  private var _focusedSurfaceID: UUID?
  /// Track which surfaces are owned by this container (vs borrowed from terminal manager)
  private var _ownedSurfaceIDs: Set<UUID> = []

  var tree: SplitTree<GhosttySurfaceView> { _tree }
  var surfaces: [UUID: GhosttySurfaceView] { _surfaces }
  var isEmpty: Bool { _tree.isEmpty }

  init(
    runtime: GhosttyRuntime,
    primaryWorktree: Worktree,
    terminalManager: WorktreeTerminalManager? = nil
  ) {
    self.runtime = runtime
    self.primaryWorktree = primaryWorktree
    self.terminalManager = terminalManager
    self._tree = SplitTree()

    let initialSurface = getOrCreateSurface(for: primaryWorktree)
    _surfaces[initialSurface.id] = initialSurface
    _surfaceWorktrees[initialSurface.id] = primaryWorktree
    _tree = SplitTree(view: initialSurface)
    _focusedSurfaceID = initialSurface.id
  }

  /// Returns an existing surface from the terminal manager if available, otherwise creates a new one.
  private func getOrCreateSurface(for worktree: Worktree) -> GhosttySurfaceView {
    // Try to borrow existing surface from terminal manager
    if let existingSurface = terminalManager?.focusedSurface(for: worktree.id) {
      // Set up callbacks for the borrowed surface
      setupSurfaceCallbacks(existingSurface, for: worktree)
      _surfaceWorktrees[existingSurface.id] = worktree
      return existingSurface
    }

    // No existing surface, create a new one
    return createSurface(for: worktree)
  }

  private func setupSurfaceCallbacks(
    _ surface: GhosttySurfaceView,
    for worktree: Worktree
  ) {
    // Remove any existing callbacks by replacing them
    surface.bridge.onSplitAction = { [weak self, weak surface] action in
      guard let self, let surface else { return false }
      return self.performSplitAction(action, for: surface.id)
    }
    surface.bridge.onCloseRequest = { [weak self, weak surface] _ in
      guard let self, let surface else { return }
      self.handleCloseRequest(for: surface)
    }
    surface.onFocusChange = { [weak self, weak surface] focused in
      guard let self, let surface, focused else { return }
      self._focusedSurfaceID = surface.id
    }
  }

  func createSurface(for worktree: Worktree) -> GhosttySurfaceView {
    let view = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: worktree.workingDirectory,
      initialInput: nil
    )

    setupSurfaceCallbacks(view, for: worktree)

    _surfaceWorktrees[view.id] = worktree
    _ownedSurfaceIDs.insert(view.id)  // Track that we own this surface
    return view
  }

  func insertSurface(for worktree: Worktree, at destinationID: UUID, zone: TerminalSplitTreeView.DropZone) -> Bool {
    guard let destinationSurface = _surfaces[destinationID] else { return false }

    let newSurface = getOrCreateSurface(for: worktree)
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
      // Only close if we own this surface (i.e., it was newly created)
      if _ownedSurfaceIDs.contains(newSurface.id) {
        newSurface.closeSurface()
        _ownedSurfaceIDs.remove(newSurface.id)
      }
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
        _ownedSurfaceIDs.remove(newSurface.id)
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
    let isOwned = _ownedSurfaceIDs.contains(view.id)

    guard let node = _tree.find(id: view.id) else {
      // Only close if we own this surface
      if isOwned {
        view.closeSurface()
        _ownedSurfaceIDs.remove(view.id)
      }
      _surfaces.removeValue(forKey: view.id)
      _surfaceWorktrees.removeValue(forKey: view.id)
      return
    }
    let newTree = _tree.removing(node)
    // Only close if we own this surface
    if isOwned {
      view.closeSurface()
      _ownedSurfaceIDs.remove(view.id)
    }
    _surfaces.removeValue(forKey: view.id)
    _surfaceWorktrees.removeValue(forKey: view.id)

    if newTree.isEmpty {
      // Signal to close container - caller should check isEmpty
      _tree = newTree
      return
    }
    _tree = newTree
    if _focusedSurfaceID == view.id {
      _focusedSurfaceID = newTree.root?.leftmostLeaf().id
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

  private func mapSplitDirection(_ direction: GhosttySplitAction.NewDirection)
    -> SplitTree<GhosttySurfaceView>.NewDirection
  {
    switch direction {
    case .left: return .left
    case .right: return .right
    case .top: return .top
    case .down: return .down
    }
  }

  private func mapFocusDirection(_ direction: GhosttySplitAction.FocusDirection)
    -> SplitTree<GhosttySurfaceView>.FocusDirection
  {
    switch direction {
    case .previous: return .previous
    case .next: return .next
    case .left: return .spatial(.left)
    case .right: return .spatial(.right)
    case .top: return .spatial(.top)
    case .down: return .spatial(.down)
    }
  }

  private func mapResizeDirection(_ direction: GhosttySplitAction.ResizeDirection)
    -> SplitTree<GhosttySurfaceView>.SpatialDirection
  {
    switch direction {
    case .left: return .left
    case .right: return .right
    case .top: return .top
    case .down: return .down
    }
  }

  func closeAll() {
    // Only close surfaces that we own (not borrowed ones)
    for surfaceID in _ownedSurfaceIDs {
      if let surface = _surfaces[surfaceID] {
        surface.closeSurface()
      }
    }
    _ownedSurfaceIDs.removeAll()
    _surfaces.removeAll()
    _surfaceWorktrees.removeAll()
    _tree = SplitTree()
  }
}
