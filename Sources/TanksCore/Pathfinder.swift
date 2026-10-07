import Foundation

/// A* over the tile grid: 8-way movement, no diagonal corner cutting, rubble costs double.
public enum Pathfinder {
    private static let directions = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]

    /// `avoiding` tiles (e.g. ones occupied by other tanks) are treated as impassable,
    /// except the start and goal themselves.
    public static func findPath(in map: TileMap, from start: GridPoint, to goal: GridPoint,
                                avoiding: Set<GridPoint> = []) -> [GridPoint]? {
        guard map[start].isPassable, map[goal].isPassable else { return nil }
        if start == goal { return [start] }

        var open = MinHeap()
        var closed: Set<GridPoint> = []
        var cameFrom: [GridPoint: GridPoint] = [:]
        var cost: [GridPoint: Int] = [start: 0]
        open.push(start, priority: heuristic(start, goal))

        while let current = open.pop() {
            if current == goal { return reconstruct(cameFrom, to: goal) }
            if closed.contains(current) { continue }
            closed.insert(current)
            let currentCost = cost[current]!

            for (dx, dy) in directions {
                let next = GridPoint(current.x + dx, current.y + dy)
                guard let tileCost = map[next].moveCost, !closed.contains(next) else { continue }
                if next != goal && avoiding.contains(next) { continue }
                let diagonal = dx != 0 && dy != 0
                if diagonal && (!map[x: current.x + dx, y: current.y].isPassable || !map[x: current.x, y: current.y + dy].isPassable) {
                    continue
                }
                let tentative = currentCost + (diagonal ? 14 : 10) * tileCost
                if tentative < cost[next, default: .max] {
                    cost[next] = tentative
                    cameFrom[next] = current
                    open.push(next, priority: tentative + heuristic(next, goal))
                }
            }
        }
        return nil
    }

    /// Octile distance in the same units as step costs.
    static func heuristic(_ a: GridPoint, _ b: GridPoint) -> Int {
        let dx = abs(a.x - b.x)
        let dy = abs(a.y - b.y)
        return 10 * (dx + dy) - 6 * min(dx, dy)
    }

    private static func reconstruct(_ cameFrom: [GridPoint: GridPoint], to goal: GridPoint) -> [GridPoint] {
        var path = [goal]
        var current = goal
        while let previous = cameFrom[current] {
            path.append(previous)
            current = previous
        }
        return path.reversed()
    }
}

/// Binary min-heap keyed by integer priority.
struct MinHeap {
    private var items: [(point: GridPoint, priority: Int)] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ point: GridPoint, priority: Int) {
        items.append((point, priority))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].priority < items[parent].priority else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> GridPoint? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < items.count && items[left].priority < items[smallest].priority { smallest = left }
            if right < items.count && items[right].priority < items[smallest].priority { smallest = right }
            if smallest == parent { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top.point
    }
}
