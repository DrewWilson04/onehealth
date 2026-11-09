import UIKit
import BackgroundTasks
import PulseKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PulseKitConfig.bootstrap()
        WatchBridge.shared.activate()
        registerBackgroundTasks()
        // HealthKit background delivery requires observer queries to be set up
        // at launch, including background launches triggered by HealthKit.
        AppServices.shared.startObserversIfAuthorized()
        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: PulseKitConfig.backfillTaskIdentifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task {
                await AppServices.shared.ingestion.runBackfill()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                // Progress is checkpointed per chunk; the next run resumes.
            }
            AppServices.scheduleBackgroundWork()
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: PulseKitConfig.refreshTaskIdentifier, using: nil) { task in
            let work = Task {
                await AppServices.shared.ingestion.refreshAll()
                await AppServices.shared.afterDataChange()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
            AppServices.scheduleBackgroundWork()
        }
    }
}
