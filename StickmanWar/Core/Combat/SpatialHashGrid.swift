import Foundation

/// 空间邻域单次命中条目（纯栈值类型，零堆分配）
public struct SpatialHitEntry: Sendable, Equatable {
    public let unitIndex: Int
    public let distanceSquared: Double

    @inline(__always)
    public init(unitIndex: Int, distanceSquared: Double) {
        self.unitIndex = unitIndex
        self.distanceSquared = distanceSquared
    }
}

/// 定长栈上空间查询结果缓冲（最多容纳 32 个邻域命中单位，完全分配在栈帧寄存器/栈内存上，零 ARC / 零堆开销，
/// 且彻底消除闭包借用 `self.spatialGrid` 期间修改 `self.soldiers` 的 Swift 6 Law-of-Exclusivity 独占访问冲突）
public struct SpatialQueryBuffer: Sendable, Equatable {
    public static let capacity: Int = 32

    public private(set) var count: Int = 0
    private var u0: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) = (-1, -1, -1, -1, -1, -1, -1, -1)
    private var u1: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) = (-1, -1, -1, -1, -1, -1, -1, -1)
    private var u2: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) = (-1, -1, -1, -1, -1, -1, -1, -1)
    private var u3: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) = (-1, -1, -1, -1, -1, -1, -1, -1)

    private var d0: (Double, Double, Double, Double, Double, Double, Double, Double) = (0, 0, 0, 0, 0, 0, 0, 0)
    private var d1: (Double, Double, Double, Double, Double, Double, Double, Double) = (0, 0, 0, 0, 0, 0, 0, 0)
    private var d2: (Double, Double, Double, Double, Double, Double, Double, Double) = (0, 0, 0, 0, 0, 0, 0, 0)
    private var d3: (Double, Double, Double, Double, Double, Double, Double, Double) = (0, 0, 0, 0, 0, 0, 0, 0)

    public init() {}

    public static func == (lhs: SpatialQueryBuffer, rhs: SpatialQueryBuffer) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for idx in 0..<lhs.count {
            if lhs[idx] != rhs[idx] {
                return false
            }
        }
        return true
    }

    @inline(__always)
    public mutating func append(unitIndex: Int, distanceSquared: Double) {
        guard count < Self.capacity else { return }
        let idx32 = Int32(unitIndex)
        switch count {
        case 0: u0.0 = idx32; d0.0 = distanceSquared
        case 1: u0.1 = idx32; d0.1 = distanceSquared
        case 2: u0.2 = idx32; d0.2 = distanceSquared
        case 3: u0.3 = idx32; d0.3 = distanceSquared
        case 4: u0.4 = idx32; d0.4 = distanceSquared
        case 5: u0.5 = idx32; d0.5 = distanceSquared
        case 6: u0.6 = idx32; d0.6 = distanceSquared
        case 7: u0.7 = idx32; d0.7 = distanceSquared
        case 8: u1.0 = idx32; d1.0 = distanceSquared
        case 9: u1.1 = idx32; d1.1 = distanceSquared
        case 10: u1.2 = idx32; d1.2 = distanceSquared
        case 11: u1.3 = idx32; d1.3 = distanceSquared
        case 12: u1.4 = idx32; d1.4 = distanceSquared
        case 13: u1.5 = idx32; d1.5 = distanceSquared
        case 14: u1.6 = idx32; d1.6 = distanceSquared
        case 15: u1.7 = idx32; d1.7 = distanceSquared
        case 16: u2.0 = idx32; d2.0 = distanceSquared
        case 17: u2.1 = idx32; d2.1 = distanceSquared
        case 18: u2.2 = idx32; d2.2 = distanceSquared
        case 19: u2.3 = idx32; d2.3 = distanceSquared
        case 20: u2.4 = idx32; d2.4 = distanceSquared
        case 21: u2.5 = idx32; d2.5 = distanceSquared
        case 22: u2.6 = idx32; d2.6 = distanceSquared
        case 23: u2.7 = idx32; d2.7 = distanceSquared
        case 24: u3.0 = idx32; d3.0 = distanceSquared
        case 25: u3.1 = idx32; d3.1 = distanceSquared
        case 26: u3.2 = idx32; d3.2 = distanceSquared
        case 27: u3.3 = idx32; d3.3 = distanceSquared
        case 28: u3.4 = idx32; d3.4 = distanceSquared
        case 29: u3.5 = idx32; d3.5 = distanceSquared
        case 30: u3.6 = idx32; d3.6 = distanceSquared
        case 31: u3.7 = idx32; d3.7 = distanceSquared
        default: break
        }
        count += 1
    }

    @inline(__always)
    public subscript(position: Int) -> SpatialHitEntry {
        switch position {
        case 0: return SpatialHitEntry(unitIndex: Int(u0.0), distanceSquared: d0.0)
        case 1: return SpatialHitEntry(unitIndex: Int(u0.1), distanceSquared: d0.1)
        case 2: return SpatialHitEntry(unitIndex: Int(u0.2), distanceSquared: d0.2)
        case 3: return SpatialHitEntry(unitIndex: Int(u0.3), distanceSquared: d0.3)
        case 4: return SpatialHitEntry(unitIndex: Int(u0.4), distanceSquared: d0.4)
        case 5: return SpatialHitEntry(unitIndex: Int(u0.5), distanceSquared: d0.5)
        case 6: return SpatialHitEntry(unitIndex: Int(u0.6), distanceSquared: d0.6)
        case 7: return SpatialHitEntry(unitIndex: Int(u0.7), distanceSquared: d0.7)
        case 8: return SpatialHitEntry(unitIndex: Int(u1.0), distanceSquared: d1.0)
        case 9: return SpatialHitEntry(unitIndex: Int(u1.1), distanceSquared: d1.1)
        case 10: return SpatialHitEntry(unitIndex: Int(u1.2), distanceSquared: d1.2)
        case 11: return SpatialHitEntry(unitIndex: Int(u1.3), distanceSquared: d1.3)
        case 12: return SpatialHitEntry(unitIndex: Int(u1.4), distanceSquared: d1.4)
        case 13: return SpatialHitEntry(unitIndex: Int(u1.5), distanceSquared: d1.5)
        case 14: return SpatialHitEntry(unitIndex: Int(u1.6), distanceSquared: d1.6)
        case 15: return SpatialHitEntry(unitIndex: Int(u1.7), distanceSquared: d1.7)
        case 16: return SpatialHitEntry(unitIndex: Int(u2.0), distanceSquared: d2.0)
        case 17: return SpatialHitEntry(unitIndex: Int(u2.1), distanceSquared: d2.1)
        case 18: return SpatialHitEntry(unitIndex: Int(u2.2), distanceSquared: d2.2)
        case 19: return SpatialHitEntry(unitIndex: Int(u2.3), distanceSquared: d2.3)
        case 20: return SpatialHitEntry(unitIndex: Int(u2.4), distanceSquared: d2.4)
        case 21: return SpatialHitEntry(unitIndex: Int(u2.5), distanceSquared: d2.5)
        case 22: return SpatialHitEntry(unitIndex: Int(u2.6), distanceSquared: d2.6)
        case 23: return SpatialHitEntry(unitIndex: Int(u2.7), distanceSquared: d2.7)
        case 24: return SpatialHitEntry(unitIndex: Int(u3.0), distanceSquared: d3.0)
        case 25: return SpatialHitEntry(unitIndex: Int(u3.1), distanceSquared: d3.1)
        case 26: return SpatialHitEntry(unitIndex: Int(u3.2), distanceSquared: d3.2)
        case 27: return SpatialHitEntry(unitIndex: Int(u3.3), distanceSquared: d3.3)
        case 28: return SpatialHitEntry(unitIndex: Int(u3.4), distanceSquared: d3.4)
        case 29: return SpatialHitEntry(unitIndex: Int(u3.5), distanceSquared: d3.5)
        case 30: return SpatialHitEntry(unitIndex: Int(u3.6), distanceSquared: d3.6)
        default: return SpatialHitEntry(unitIndex: Int(u3.7), distanceSquared: d3.7)
        }
    }
}

/// 均匀空间哈希网格（Uniform Spatial Hash Grid，单桶 120×120 px，静态索引链表 + SoA 坐标缓存）
/// 严格兑现 DESIGN.md 11.2 性能优化铁律：
/// 1. 预分配定长 `cellHead` 与 `unitNext` 静态链表数组，每逻辑帧 O(N) 重建，完全零堆内存分配；
/// 2. 提供定长栈值返回 `queryInRadius` 接口，检索完毕即释放 `self.spatialGrid` 借用，100% 满足 Swift 6 独占访问安全。
public struct SpatialHashGrid: Sendable, Equatable {
    public let cellSize: Double
    public let invCellSize: Double
    public let worldWidth: Double
    public let worldHeight: Double
    public let cols: Int
    public let rows: Int
    public let maxUnits: Int

    /// 每个网格桶的首个士兵下标（-1 表示空桶）
    private var cellHead: [Int32]
    /// 同一网格桶内下一名士兵的静态单向链表下标（-1 表示链尾）
    private var unitNext: [Int32]

    /// SoA 紧凑缓存，消除随机跳转访问大结构体的缓存未命中
    private var cachedX: [Double]
    private var cachedY: [Double]
    private var cachedRadius: [Double]
    private var cachedSide: [Int8]
    private var cachedConcealed: [Bool]

    public init(
        worldWidth: Double = GameConstants.battlefieldWidth,
        worldHeight: Double = GameConstants.battlefieldHeight,
        cellSize: Double = GameConstants.spatialGridCellSize,
        maxUnits: Int = GameConstants.maxUnitPoolSize
    ) {
        let safeCell = max(16.0, cellSize)
        let computedCols = max(1, Int(ceil(worldWidth / safeCell)))
        let computedRows = max(1, Int(ceil(worldHeight / safeCell)))

        self.cellSize = safeCell
        self.invCellSize = 1.0 / safeCell
        self.worldWidth = worldWidth
        self.worldHeight = worldHeight
        self.cols = computedCols
        self.rows = computedRows
        self.maxUnits = maxUnits

        self.cellHead = Array(repeating: -1, count: computedCols * computedRows)
        self.unitNext = Array(repeating: -1, count: maxUnits)
        self.cachedX = Array(repeating: 0.0, count: maxUnits)
        self.cachedY = Array(repeating: 0.0, count: maxUnits)
        self.cachedRadius = Array(repeating: 8.0, count: maxUnits)
        self.cachedSide = Array(repeating: -1, count: maxUnits)
        self.cachedConcealed = Array(repeating: false, count: maxUnits)
    }

    /// 清空全部网格桶头指针（原地覆写 -1，零重分配）
    public mutating func clear() {
        for i in 0..<cellHead.count {
            cellHead[i] = -1
        }
    }

    /// 将单个存活士兵插入对应空间桶
    @inline(__always)
    public mutating func insert(
        unitIndex: Int,
        x: Double,
        y: Double,
        radius: Double,
        side: BattleSide,
        isConcealed: Bool = false
    ) {
        guard unitIndex >= 0 && unitIndex < maxUnits else { return }
        let cx = clampCol(Int(x * invCellSize))
        let cy = clampRow(Int(y * invCellSize))
        let bucket = cy * cols + cx

        cachedX[unitIndex] = x
        cachedY[unitIndex] = y
        cachedRadius[unitIndex] = radius
        cachedSide[unitIndex] = Int8(side.rawValue)
        cachedConcealed[unitIndex] = isConcealed

        unitNext[unitIndex] = cellHead[bucket]
        cellHead[bucket] = Int32(unitIndex)
    }

    /// 每逻辑帧 O(N) 重建全图空间网格（注意：密林内正在开火或近战挥击的单位会暴露自身位置，仅未开火潜伏者保持隐蔽）
    public mutating func rebuild(from soldiers: [SoldierEntity], terrainZones: [TerrainZoneRect]) {
        clear()
        let limit = min(maxUnits, soldiers.count)
        for idx in 0..<limit {
            let unit = soldiers[idx]
            guard unit.isActive,
                  unit.hp > 0.0,
                  unit.actionState != .dyingFall,
                  unit.actionState != .fallenCorpse,
                  !unit.isGarrisonedInCamp else {
                cachedSide[idx] = -1
                continue
            }
            var inForest = false
            for zIdx in 0..<terrainZones.count {
                let zone = terrainZones[zIdx]
                if zone.terrain == .denseForest && zone.contains(x: unit.x, y: unit.y) {
                    inForest = true
                    break
                }
            }
            let unrevealedInForest = inForest
                && unit.outOfCombatTimer >= 1.5
                && unit.actionState != .meleeStrike
                && unit.actionState != .rangedDrawFire
            insert(
                unitIndex: idx,
                x: unit.x,
                y: unit.y,
                radius: unit.collisionRadius,
                side: unit.side,
                isConcealed: unit.isStealthed || unrevealedInForest
            )
        }
    }

    /// 零堆分配检索圆形半径内的单位并返回定长栈结构 `SpatialQueryBuffer`（最多 `maxResults <= 32` 个）
    public func queryInRadius(
        centerX: Double,
        centerY: Double,
        radius: Double,
        sideFilter: BattleSide? = nil,
        excludeUnitIndex: Int = -1,
        maxResults: Int = SpatialQueryBuffer.capacity
    ) -> SpatialQueryBuffer {
        var buffer = SpatialQueryBuffer()
        guard radius > 0.0, maxResults > 0 else { return buffer }
        let cap = min(SpatialQueryBuffer.capacity, maxResults)
        let rSq = radius * radius
        let minCol = clampCol(Int((centerX - radius) * invCellSize))
        let maxCol = clampCol(Int((centerX + radius) * invCellSize))
        let minRow = clampRow(Int((centerY - radius) * invCellSize))
        let maxRow = clampRow(Int((centerY + radius) * invCellSize))
        let targetSideRaw: Int8? = sideFilter.map { Int8($0.rawValue) }

        for row in minRow...maxRow {
            let rowOffset = row * cols
            for col in minCol...maxCol {
                var cur = Int(cellHead[rowOffset + col])
                while cur != -1 {
                    if cur != excludeUnitIndex {
                        if let expectedSide = targetSideRaw, cachedSide[cur] != expectedSide {
                            // 跳过非目标阵营
                        } else {
                            let dx = cachedX[cur] - centerX
                            let dy = cachedY[cur] - centerY
                            let distSq = dx * dx + dy * dy
                            if distSq <= rSq {
                                buffer.append(unitIndex: cur, distanceSquared: distSq)
                                if buffer.count >= cap {
                                    return buffer
                                }
                            }
                        }
                    }
                    cur = Int(unitNext[cur])
                }
            }
        }
        return buffer
    }

    /// 扫描圆形半径内的单位并回调 `(unitIndex, distanceSquared)`（适合只读统计与独立外部测试）
    public func forEachInRadius(
        centerX: Double,
        centerY: Double,
        radius: Double,
        sideFilter: BattleSide? = nil,
        excludeUnitIndex: Int = -1,
        _ body: (Int, Double) -> Void
    ) {
        guard radius > 0.0 else { return }
        let rSq = radius * radius
        let minCol = clampCol(Int((centerX - radius) * invCellSize))
        let maxCol = clampCol(Int((centerX + radius) * invCellSize))
        let minRow = clampRow(Int((centerY - radius) * invCellSize))
        let maxRow = clampRow(Int((centerY + radius) * invCellSize))
        let targetSideRaw: Int8? = sideFilter.map { Int8($0.rawValue) }

        for row in minRow...maxRow {
            let rowOffset = row * cols
            for col in minCol...maxCol {
                var cur = Int(cellHead[rowOffset + col])
                while cur != -1 {
                    let next = Int(unitNext[cur])
                    if cur != excludeUnitIndex {
                        if let expectedSide = targetSideRaw, cachedSide[cur] != expectedSide {
                            // 阵营不匹配
                        } else {
                            let dx = cachedX[cur] - centerX
                            let dy = cachedY[cur] - centerY
                            let distSq = dx * dx + dy * dy
                            if distSq <= rSq {
                                body(cur, distSq)
                            }
                        }
                    }
                    cur = next
                }
            }
        }
    }

    /// O(邻域桶) 检索距离指定坐标最近且满足最小盲区与密林潜行反隐规则的敌军单位下标（未找到返回 -1）
    public func findNearestEnemy(
        fromX: Double,
        fromY: Double,
        enemySide: BattleSide,
        maxRange: Double,
        minRange: Double = 0.0,
        viewerFaction: FactionId = .yanlong,
        viewerIsCavalryScout: Bool = false
    ) -> Int {
        guard maxRange > 0.0 else { return -1 }
        let maxSq = maxRange * maxRange
        let minSq = minRange > 0.0 ? (minRange * minRange) : 0.0
        let forestRevealSq = GameConstants.forestStealthRevealRadius * GameConstants.forestStealthRevealRadius
        let expectedSide = Int8(enemySide.rawValue)

        let minCol = clampCol(Int((fromX - maxRange) * invCellSize))
        let maxCol = clampCol(Int((fromX + maxRange) * invCellSize))
        let minRow = clampRow(Int((fromY - maxRange) * invCellSize))
        let maxRow = clampRow(Int((fromY + maxRange) * invCellSize))

        var bestIndex: Int = -1
        var bestDistSq: Double = maxSq

        for row in minRow...maxRow {
            let rowOffset = row * cols
            for col in minCol...maxCol {
                var cur = Int(cellHead[rowOffset + col])
                while cur != -1 {
                    if cachedSide[cur] == expectedSide {
                        let dx = cachedX[cur] - fromX
                        let dy = cachedY[cur] - fromY
                        let dSq = dx * dx + dy * dy
                        if dSq <= bestDistSq && dSq >= minSq {
                            let hidden = cachedConcealed[cur]
                            let canSpot: Bool
                            if !hidden || viewerFaction == .wulin {
                                canSpot = true
                            } else {
                                let revealLimitSq = viewerIsCavalryScout ? (forestRevealSq * 2.25) : forestRevealSq
                                canSpot = dSq <= revealLimitSq
                            }
                            if canSpot {
                                bestDistSq = dSq
                                bestIndex = cur
                            }
                        }
                    }
                    cur = Int(unitNext[cur])
                }
            }
        }
        return bestIndex
    }

    /// 统计圆形区域内的单位数量
    public func countUnitsInRadius(
        centerX: Double,
        centerY: Double,
        radius: Double,
        sideFilter: BattleSide? = nil
    ) -> Int {
        var count = 0
        forEachInRadius(centerX: centerX, centerY: centerY, radius: radius, sideFilter: sideFilter) { _, _ in
            count += 1
        }
        return count
    }

    /// 读取缓存的单位坐标与碰撞半径
    @inline(__always)
    public func cachedPositionAndRadius(of unitIndex: Int) -> (x: Double, y: Double, radius: Double) {
        (cachedX[unitIndex], cachedY[unitIndex], cachedRadius[unitIndex])
    }

    @inline(__always)
    private func clampCol(_ col: Int) -> Int {
        if col < 0 { return 0 }
        if col >= cols { return cols - 1 }
        return col
    }

    @inline(__always)
    private func clampRow(_ row: Int) -> Int {
        if row < 0 { return 0 }
        if row >= rows { return rows - 1 }
        return row
    }
}
