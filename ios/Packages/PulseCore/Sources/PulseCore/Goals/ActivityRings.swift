import Foundation

/// Apple-style activity rings for one day (move kcal, exercise min, stand h).
public struct ActivityRings: Codable, Sendable, Hashable {
    public var move: Double
    public var moveGoal: Double
    public var exercise: Double
    public var exerciseGoal: Double
    public var stand: Double
    public var standGoal: Double

    public init(move: Double, moveGoal: Double, exercise: Double, exerciseGoal: Double, stand: Double, standGoal: Double) {
        self.move = move
        self.moveGoal = moveGoal
        self.exercise = exercise
        self.exerciseGoal = exerciseGoal
        self.stand = stand
        self.standGoal = standGoal
    }

    public var moveProgress: Double { moveGoal > 0 ? move / moveGoal : 0 }
    public var exerciseProgress: Double { exerciseGoal > 0 ? exercise / exerciseGoal : 0 }
    public var standProgress: Double { standGoal > 0 ? stand / standGoal : 0 }
    public var allClosed: Bool { moveProgress >= 1 && exerciseProgress >= 1 && standProgress >= 1 }
}
