import Foundation

public enum LineOfSight {
    /// Bresenham walk between two tiles. The endpoints never block, and tiles of
    /// `ignoringBuilding` never block (so a soldier can see out of their own building).
    public static func isClear(in map: TileMap, from a: GridPoint, to b: GridPoint, ignoringBuilding: Int? = nil) -> Bool {
        var x = a.x
        var y = a.y
        let dx = abs(b.x - a.x)
        let dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1
        let sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while !(x == b.x && y == b.y) {
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
            if x == b.x && y == b.y { break }
            let tile = map[x: x, y: y]
            if tile.blocksSight && (tile.buildingID == nil || tile.buildingID != ignoringBuilding) {
                return false
            }
        }
        return true
    }
}
