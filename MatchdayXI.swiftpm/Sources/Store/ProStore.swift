import Foundation
import Observation
import StoreKit

/// Handles the one-off "Matchday XI Pro" in-app purchase.
///
/// Setup: in App Store Connect, create a **Non-Consumable** in-app purchase whose
/// Product ID matches `productID` below, and set its price (e.g. 3.99).
@MainActor
@Observable
final class ProStore {
    static let productID = "com.matchdayxi.app.pro"

    /// Limits for the free version.
    static let freePlayerLimit = 20
    static let freeLineupLimit = 3

    private(set) var product: Product?
    private(set) var hasPurchased: Bool
    private(set) var testUnlock: Bool
    private(set) var canUseTestUnlock = false
    private(set) var isWorking = false
    private(set) var hasLoadedProduct = false
    var errorMessage: String?

    var isPro: Bool { hasPurchased || testUnlock }

    private static let purchasedCacheKey = "pro.purchased"
    private static let testUnlockKey = "pro.testUnlock"

    init() {
        hasPurchased = UserDefaults.standard.bool(forKey: Self.purchasedCacheKey)
        testUnlock = UserDefaults.standard.bool(forKey: Self.testUnlockKey)

        // Purchases can arrive outside the app (e.g. Ask to Buy, another device, refunds).
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    // MARK: - Free limits

    func canAddPlayer(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freePlayerLimit
    }

    func canHavePlayers(_ count: Int) -> Bool {
        isPro || count <= Self.freePlayerLimit
    }

    func canAddLineup(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeLineupLimit
    }

    // MARK: - StoreKit

    func refresh() async {
        await loadProduct()
        await updateEntitlements()
        await checkTestMode()
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            print("Failed to load products: \(error)")
        }
        hasLoadedProduct = true
    }

    func purchase() async {
        guard let product else {
            errorMessage = "Pro isn't available to buy right now. Please try again later."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    setPurchased(true)
                } else {
                    errorMessage = "The purchase couldn't be verified."
                }
            case .pending:
                errorMessage = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await updateEntitlements()
        if !hasPurchased {
            errorMessage = "No previous Pro purchase was found for this Apple ID."
        }
    }

    private func updateEntitlements() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        setPurchased(purchased)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            setPurchased(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func setPurchased(_ purchased: Bool) {
        hasPurchased = purchased
        UserDefaults.standard.set(purchased, forKey: Self.purchasedCacheKey)
    }

    // MARK: - Testing

    /// A switch to try Pro features without paying. It only appears in test builds
    /// (Swift Playgrounds, Xcode, TestFlight), never in the App Store version.
    private func checkTestMode() async {
        #if DEBUG
        canUseTestUnlock = true
        #else
        if let result = try? await AppTransaction.shared, case .verified(let transaction) = result {
            canUseTestUnlock = transaction.environment != .production
        } else {
            canUseTestUnlock = false
        }
        #endif
        if !canUseTestUnlock && testUnlock {
            setTestUnlock(false)
        }
    }

    func setTestUnlock(_ enabled: Bool) {
        testUnlock = enabled
        UserDefaults.standard.set(enabled, forKey: Self.testUnlockKey)
    }
}
