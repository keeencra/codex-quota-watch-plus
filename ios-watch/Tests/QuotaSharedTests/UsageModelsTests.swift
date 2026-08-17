import XCTest
@testable import QuotaShared

final class UsageModelsTests: XCTestCase {
    func testWatchSnapshotDecodesCompactPayload() throws {
        let json = """
        {
          "updated_at": "2026-06-12T12:00:00Z",
          "codex": {
            "remaining_percent": 72,
            "used_percent": 28,
            "reset_in": "3h 12m",
            "window": "5h",
            "status": "ok",
            "source": "codex app-server account/rateLimits/read",
            "quota_updated_at": "2026-06-12T11:59:00Z",
            "today_tokens": 1250000,
            "today_input_tokens": 1000,
            "today_output_tokens": 2000,
            "today_cache_tokens": 3000,
            "hourly": [
              {
                "hour": 0,
                "tokens": 12
              },
              {
                "hour": 1,
                "tokens": 34
              }
            ],
            "buckets": [
              {
                "id": "codex:primary",
                "label": "codex 5h",
                "remaining_percent": 72,
                "used_percent": 28,
                "reset_in": "3h 12m",
                "window": "5h",
                "status": "ok"
              }
            ]
          }
        }
        """

        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.updatedAt, "2026-06-12T12:00:00Z")
        XCTAssertEqual(snapshot.codex.remainingPercent, 72)
        XCTAssertEqual(snapshot.codex.todayTokens, 1_250_000)
        XCTAssertEqual(snapshot.codex.todayCacheTokens, 3_000)
        XCTAssertEqual(snapshot.codex.hourly.first?.hour, 0)
        XCTAssertEqual(snapshot.codex.hourly.first?.tokens, 12)
        XCTAssertEqual(snapshot.codex.buckets?.first?.stableID, "codex:primary")
    }

    func testWatchSnapshotDecodesMinimalPayload() throws {
        let json = """
        {
          "updated_at": "2026-06-12T12:00:00Z",
          "codex": {
            "status": "ok",
            "source": "test",
            "today_tokens": 0
          }
        }
        """

        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))

        XCTAssertTrue(snapshot.codex.hourly.isEmpty)
    }

    func testWatchSnapshotDecodesProviderError() throws {
        let json = """
        {
          "updated_at": "2026-06-12T12:00:00Z",
          "codex": {
            "status": "error",
            "source": "scanner",
            "error": "failed to scan <codex_home>",
            "today_tokens": 0
          }
        }
        """

        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.codex.error, "failed to scan <codex_home>")
    }

    func testTokenFormattingUsesCompactUnits() {
        XCTAssertEqual(NumberFormatters.compactTokens(999), "999")
        XCTAssertEqual(NumberFormatters.compactTokens(1_500), "1.5K")
        XCTAssertEqual(NumberFormatters.compactTokens(1_260_000), "1.3M")
    }

    func testQuotaDisplayTextUsesBucketValuesForCompactQuotaUI() {
        let fallback = ProviderUsage.placeholder(status: "ok")
        let bucket = QuotaBucket(
            id: "codex:primary",
            label: "codex 5h",
            remainingPercent: 72,
            usedPercent: 28,
            resetIn: "3h 12m",
            window: "5h",
            status: "ok"
        )

        XCTAssertEqual(QuotaDisplayText.remainingPercent(bucket: bucket, fallback: fallback), 72)
        XCTAssertEqual(QuotaDisplayText.usedPercent(bucket: bucket, fallback: fallback), 28)
        XCTAssertEqual(QuotaDisplayText.usedLabel(bucket: bucket, fallback: fallback), "已用 28%")
        XCTAssertEqual(QuotaDisplayText.resetLabel(bucket: bucket, fallback: fallback), "重置 3h 12m")
    }

    func testQuotaDisplayTextInfersUsedPercentFromRemainingPercent() {
        var fallback = ProviderUsage.placeholder(status: "ok")
        fallback.remainingPercent = 64

        XCTAssertEqual(QuotaDisplayText.usedPercent(bucket: nil, fallback: fallback), 36)
        XCTAssertEqual(QuotaDisplayText.usedLabel(bucket: nil, fallback: fallback), "已用 36%")
        XCTAssertEqual(QuotaDisplayText.resetLabel(bucket: nil, fallback: fallback), "重置 --")
    }

    func testQuotaDisplayTreatsTenPercentRemainingAsCritical() {
        XCTAssertTrue(QuotaDisplayText.isCriticalRemaining(10))
        XCTAssertTrue(QuotaDisplayText.isCriticalRemaining(9.9))
        XCTAssertFalse(QuotaDisplayText.isCriticalRemaining(10.1))
        XCTAssertFalse(QuotaDisplayText.isCriticalRemaining(nil))
    }

    func testCodexFooterUsesSelectedCodexLimitDisplayName() {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.buckets = [
            QuotaBucket(
                id: "codex:primary",
                label: "codex 5h",
                remainingPercent: 45,
                usedPercent: 55,
                resetIn: "1h",
                window: "5h",
                status: "ok"
            ),
            QuotaBucket(
                id: "GPT-5.3-Codex-Spark:primary",
                label: "GPT-5.3-Codex-Spark 5h",
                remainingPercent: 100,
                usedPercent: 0,
                resetIn: "1h",
                window: "5h",
                status: "ok"
            ),
        ]
        let selection = WatchDisplayData.codexWindows(from: usage.buckets)

        XCTAssertEqual(QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: usage), "GPT-5.5")
    }

    func testCodexFooterPrefersCodexModelEvenWhenSelectionIsSpark() {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.buckets = [
            QuotaBucket(
                id: "codex_bengalfox:primary",
                label: "GPT-5.3-Codex-Spark 5h",
                remainingPercent: 100,
                usedPercent: 0,
                resetIn: "1h",
                window: "5h",
                status: "ok"
            ),
            QuotaBucket(
                id: "codex:secondary",
                label: "codex 7d secondary",
                remainingPercent: 17,
                usedPercent: 83,
                resetIn: "2d 14h",
                window: "7d",
                status: "ok"
            ),
        ]
        let selection = CodexWindowSelection(fiveHour: usage.buckets?.first, sevenDay: nil)

        XCTAssertEqual(QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: usage), "GPT-5.5")
    }

    func testCodexFooterPreservesSelectedNamedLimitWhenCodexBucketIsMissing() {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.buckets = [
            QuotaBucket(
                id: "gpt-5.3-spark:primary",
                label: "GPT-5.3-Spark 5h",
                remainingPercent: 100,
                usedPercent: 0,
                resetIn: "1h",
                window: "5h",
                status: "ok"
            ),
        ]
        let selection = WatchDisplayData.codexWindows(from: usage.buckets)

        XCTAssertEqual(QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: usage), "GPT-5.3-Spark")
    }

    func testCodexFooterDoesNotFallbackToGenericCodexAsModelName() {
        var usage = ProviderUsage.placeholder(status: "ok")
        usage.buckets = [
            QuotaBucket(
                id: "codex:primary",
                label: "codex 5h",
                remainingPercent: 45,
                usedPercent: 55,
                resetIn: "1h",
                window: "5h",
                status: "ok"
            ),
        ]

        let selection = WatchDisplayData.codexWindows(from: usage.buckets)

        XCTAssertEqual(QuotaDisplayText.codexFooterModelLabel(selection: selection, fallback: usage), "GPT-5.5")
    }

    func testWatchUpdateLabelUsesSpecificSnapshotTime() {
        let snapshot = WatchSnapshot(
            updatedAt: "2026-06-12T12:00:00Z",
            codex: ProviderUsage.placeholder(status: "ok")
        )

        XCTAssertEqual(
            QuotaDisplayText.watchUpdateLabel(snapshot: snapshot, timeZone: TimeZone(secondsFromGMT: 0)!),
            "刷新 12:00"
        )
    }

    func testWatchUpdateLabelUsesCodexQuotaTimeWhenCacheIsOlderThanSnapshot() {
        var codex = ProviderUsage.placeholder(status: "ok")
        codex.quotaUpdatedAt = "2026-06-12T11:58:00Z"
        let snapshot = WatchSnapshot(
            updatedAt: "2026-06-12T12:00:00Z",
            codex: codex
        )

        XCTAssertEqual(
            QuotaDisplayText.watchUpdateLabel(snapshot: snapshot, timeZone: TimeZone(secondsFromGMT: 0)!),
            "刷新 11:58"
        )
    }

    func testResetTimeLabelUsesSpecificResetClockTime() {
        let snapshot = WatchSnapshot(
            updatedAt: "2026-06-12T12:00:00Z",
            codex: ProviderUsage.placeholder(status: "ok")
        )
        let fallback = ProviderUsage.placeholder(status: "ok")
        let sameDayBucket = QuotaBucket(
            id: "codex:primary",
            label: "codex 5h",
            remainingPercent: 45,
            usedPercent: 55,
            resetIn: "3h 12m",
            window: "5h",
            status: "ok"
        )
        let laterBucket = QuotaBucket(
            id: "codex:secondary",
            label: "codex 7d",
            remainingPercent: 45,
            usedPercent: 55,
            resetIn: "2d 6h",
            window: "7d",
            status: "ok"
        )

        XCTAssertEqual(
            QuotaDisplayText.resetTimeLabel(
                bucket: sameDayBucket,
                fallback: fallback,
                snapshot: snapshot,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "15:12"
        )
        XCTAssertEqual(
            QuotaDisplayText.resetTimeLabel(
                bucket: laterBucket,
                fallback: fallback,
                snapshot: snapshot,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "06/14 18:00"
        )
    }

    func testHourlyUsageIntensityIsClamped() {
        XCTAssertEqual(HourlyUsage(hour: 0, tokens: 0).intensity(maxTokens: 100), 0)
        XCTAssertEqual(HourlyUsage(hour: 1, tokens: 50).intensity(maxTokens: 100), 0.5)
        XCTAssertEqual(HourlyUsage(hour: 2, tokens: 150).intensity(maxTokens: 100), 1)
        XCTAssertEqual(HourlyUsage(hour: 3, tokens: 20).intensity(maxTokens: 0), 0)
    }

    func testCodexWindowSelectionPrefersCodexLimitOverLowerSparkBucket() {
        let buckets = [
            QuotaBucket(
                id: "GPT-5.3-Codex-Spark:primary",
                label: "GPT-5.3-Codex-Spark 5h",
                remainingPercent: 3,
                usedPercent: 97,
                resetIn: "1h 2m",
                window: "5h",
                status: "ok"
            ),
            QuotaBucket(
                id: "codex:primary",
                label: "codex 5h",
                remainingPercent: 72,
                usedPercent: 28,
                resetIn: "3h 12m",
                window: "5h",
                status: "ok"
            ),
            QuotaBucket(
                id: "codex:secondary",
                label: "codex 7d",
                remainingPercent: 64,
                usedPercent: 36,
                resetIn: "4d 6h",
                window: "7d",
                status: "ok"
            ),
        ]

        let selection = WatchDisplayData.codexWindows(from: buckets)

        XCTAssertEqual(selection.fiveHour?.id, "codex:primary")
        XCTAssertEqual(selection.sevenDay?.id, "codex:secondary")
    }

    func testCodexWindowSelectionDoesNotInventMissingSevenDayBucket() {
        let buckets = [
            QuotaBucket(
                id: "codex:primary",
                label: "codex 5h",
                remainingPercent: 72,
                usedPercent: 28,
                resetIn: "3h 12m",
                window: "5h",
                status: "ok"
            ),
        ]

        let selection = WatchDisplayData.codexWindows(from: buckets)

        XCTAssertEqual(selection.fiveHour?.id, "codex:primary")
        XCTAssertNil(selection.sevenDay)
    }

    func testWatchAgentConfigRequiresValidURLAndToken() {
        let token = String(repeating: "a", count: 24)

        XCTAssertEqual(
            WatchAgentConfig.make(macURL: "http://mac-agent.example.test:8788", token: " \(token) "),
            WatchAgentConfig(macURL: "http://mac-agent.example.test:8788", token: token)
        )
        XCTAssertNil(WatchAgentConfig.make(macURL: "ftp://mac-agent.example.test:8788", token: token))
        XCTAssertNil(WatchAgentConfig.make(macURL: "http://mac-agent.example.test:8788", token: "short"))
    }

    func testWatchAgentConfigStoreRoundTripsSanitizedConfig() {
        let suiteName = "QuotaSharedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = WatchAgentConfigStore(defaults: defaults)
        let token = String(repeating: "b", count: 24)
        let config = WatchAgentConfig(macURL: "http://mac-agent.example.test:8788", token: token)

        store.save(config)

        XCTAssertEqual(store.load(), config)
    }

    func testRefreshRouteLabelsAreCompactForWatch() {
        XCTAssertEqual(WatchRefreshRoute.cached.label, "cached")
        XCTAssertEqual(WatchRefreshRoute.directRefreshing.label, "direct...")
        XCTAssertEqual(WatchRefreshRoute.directOK.label, "direct ok")
        XCTAssertEqual(WatchRefreshRoute.noConfig.label, "no config")
        XCTAssertEqual(WatchRefreshRoute.directFailed(nil).label, "direct failed")
        XCTAssertEqual(WatchRefreshRoute.directFailed("-1004").label, "direct -1004")
        XCTAssertEqual(WatchRefreshRoute.iPhone.label, "iphone")
    }

    func testWatchRefreshErrorTextKeepsDirectFailuresCompact() {
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.invalidURL), "url")
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.emptyToken), "token")
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.badResponse(401)), "http401")
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.network("offline", code: -1009)), "-1009")
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.network("unknown", code: nil)), "net")
        XCTAssertEqual(WatchRefreshErrorText.directFailureDetail(UsageClientError.invalidPayload("bad json")), "payload")
    }

    func testTwoHourTokenBinsAggregateTwentyFourHours() {
        let hours = (0..<24).map { HourlyUsage(hour: $0, tokens: $0 * 100) }

        let bins = WatchDisplayData.twoHourTokenBins(from: hours)

        XCTAssertEqual(bins.count, 12)
        XCTAssertEqual(bins.first?.startHour, 0)
        XCTAssertEqual(bins.first?.tokens, 100)
        XCTAssertEqual(bins.last?.startHour, 22)
        XCTAssertEqual(bins.last?.tokens, 4_500)
        XCTAssertEqual(bins.last?.intensity(maxTokens: 4_500), 1)
    }

    func testTwoHourTokenBinsAccumulateDuplicateHours() {
        let hours = [
            HourlyUsage(hour: 0, tokens: 100),
            HourlyUsage(hour: 0, tokens: 25),
            HourlyUsage(hour: 1, tokens: 75),
        ]

        let bins = WatchDisplayData.twoHourTokenBins(from: hours)

        XCTAssertEqual(bins.count, 12)
        XCTAssertEqual(bins.first?.tokens, 200)
    }

    func testTwoHourTokenBinsCanStopAtCurrentHour() {
        let hours = (0..<24).map { HourlyUsage(hour: $0, tokens: $0 * 100) }

        let bins = WatchDisplayData.twoHourTokenBins(from: hours, throughHour: 9)

        XCTAssertEqual(bins.map(\.startHour), [0, 2, 4, 6, 8])
        XCTAssertEqual(bins.first?.tokens, 100)
        XCTAssertEqual(bins.last?.tokens, 1_700)
    }

    func testHourlyTokenBinsUseOneColumnPerHourThroughCurrentHour() {
        let hours = (0..<24).map { HourlyUsage(hour: $0, tokens: $0 * 100) }

        let bins = WatchDisplayData.hourlyTokenBins(from: hours, throughHour: 10)

        XCTAssertEqual(bins.map(\.startHour), Array(0...10))
        XCTAssertEqual(bins.first?.tokens, 0)
        XCTAssertEqual(bins.last?.tokens, 1_000)
    }

    func testQuotaHeadlinesPreferActionableStatusForErrorsAndSetup() {
        var errorUsage = ProviderUsage.placeholder(status: "error")
        errorUsage.source = "scanner"
        errorUsage.error = "failed to scan"

        XCTAssertEqual(NumberFormatters.quotaHeadline(errorUsage), "error")
        XCTAssertEqual(WatchDisplayText.providerBadge(errorUsage, fallback: "estimate"), "error")
        XCTAssertEqual(WatchDisplayText.providerDetail(errorUsage, fallback: "local block"), "scanner error")

        let setupUsage = ProviderUsage.placeholder(status: "not_configured")
        XCTAssertEqual(NumberFormatters.quotaHeadline(setupUsage), "setup")
        XCTAssertEqual(WatchDisplayText.providerBadge(setupUsage, fallback: "estimate"), "setup")
    }

    func testQuotaHeadlineShowsStatusForLocalEstimateWithoutPercent() {
        var usage = ProviderUsage.placeholder(status: "partial")
        usage.resetIn = "2h 13m"

        XCTAssertEqual(NumberFormatters.quotaHeadline(usage), "partial")
    }

    func testSnapshotFreshnessLabelsAreWatchFriendly() {
        let snapshot = WatchSnapshot(
            updatedAt: "2026-06-12T12:00:00Z",
            codex: ProviderUsage.placeholder(status: "ok")
        )
        let formatter = ISO8601DateFormatter()

        XCTAssertEqual(
            WatchDisplayText.snapshotFooter(snapshot, now: formatter.date(from: "2026-06-12T12:04:00Z")!),
            "Updated 4m ago"
        )
        XCTAssertEqual(
            WatchDisplayText.snapshotFooter(snapshot, now: formatter.date(from: "2026-06-12T12:18:00Z")!),
            "Stale 18m ago"
        )
        XCTAssertEqual(
            WatchDisplayText.snapshotFooter(snapshot, now: formatter.date(from: "2026-06-12T14:30:00Z")!),
            "Old 2h ago"
        )
    }

    func testSnapshotRouteStatusKeepsRouteVisibleWhenDataIsStale() {
        let snapshot = WatchSnapshot(
            updatedAt: "2026-06-12T12:00:00Z",
            codex: ProviderUsage.placeholder(status: "ok")
        )
        let formatter = ISO8601DateFormatter()

        XCTAssertEqual(
            WatchDisplayText.snapshotRouteStatus(
                snapshot,
                route: .directFailed(nil),
                now: formatter.date(from: "2026-06-12T12:18:00Z")!
            ),
            "stale / direct failed"
        )
        XCTAssertEqual(
            WatchDisplayText.snapshotRouteStatus(
                snapshot,
                route: .directOK,
                now: formatter.date(from: "2026-06-12T12:04:00Z")!
            ),
            "direct ok"
        )
    }

    func testWatchLayoutMetricsClassifiesSeries7Sizes() {
        let series7Small = WatchLayoutMetrics(width: 176, height: 215)
        XCTAssertEqual(series7Small.sizeClass, .compact)
        XCTAssertLessThan(series7Small.scale, 1.0)
        XCTAssertEqual(series7Small.segmentCount, 14)

        let series7Large = WatchLayoutMetrics(width: 198, height: 242)
        XCTAssertEqual(series7Large.sizeClass, .regular)
        XCTAssertLessThan(series7Large.scale, 1.0)
        XCTAssertEqual(series7Large.segmentCount, 18)
    }

    func testWatchLayoutMetricsKeepsFullDensityForLargeWatches() {
        let ultra = WatchLayoutMetrics(width: 205, height: 251)
        XCTAssertEqual(ultra.sizeClass, .spacious)
        XCTAssertEqual(ultra.scale, 1.0)
        XCTAssertEqual(ultra.segmentCount, 20)
    }

    func testWatchLayoutMetricsAllocatesCodexHeroToFirstScreen() {
        let compact = WatchLayoutMetrics(width: 162, height: 197)
        XCTAssertEqual(compact.sizeClass, .compact)
        XCTAssertGreaterThanOrEqual(compact.codexHeroMinHeight, 185)
        XCTAssertLessThanOrEqual(compact.codexHeroMinHeight, 189)

        let regular = WatchLayoutMetrics(width: 176, height: 215)
        XCTAssertGreaterThanOrEqual(regular.codexHeroMinHeight, 205)
        XCTAssertLessThanOrEqual(regular.codexHeroMinHeight, 207)

        let ultra = WatchLayoutMetrics(width: 205, height: 251)
        XCTAssertGreaterThan(ultra.codexHeroMinHeight, regular.codexHeroMinHeight)
        XCTAssertLessThanOrEqual(ultra.codexHeroMinHeight, 241)
    }

    func testWatchLayoutMetricsMovesCodexPageTowardTopEdge() {
        let compact = WatchLayoutMetrics(width: 162, height: 197)
        let regular = WatchLayoutMetrics(width: 198, height: 242)
        let ultra = WatchLayoutMetrics(width: 205, height: 251)

        XCTAssertEqual(compact.codexPageTopOffset, -22)
        XCTAssertEqual(regular.codexPageTopOffset, -26)
        XCTAssertEqual(ultra.codexPageTopOffset, -30)
    }

    func testWatchLayoutMetricsUsesReadableSmallLabels() {
        let compact = WatchLayoutMetrics(width: 162, height: 197)
        let regular = WatchLayoutMetrics(width: 198, height: 242)
        let ultra = WatchLayoutMetrics(width: 205, height: 251)

        XCTAssertEqual(compact.quotaSubLabelFontSize, 12)
        XCTAssertEqual(regular.quotaSubLabelFontSize, 13)
        XCTAssertEqual(ultra.quotaSubLabelFontSize, 13)
        XCTAssertEqual(regular.resetTitleFontSize, 12)
        XCTAssertEqual(regular.footerMetaFontSize, 11)
    }

    func testWatchLayoutMetricsCompressesHourlyHistogramSpacingForFullDay() {
        let regular = WatchLayoutMetrics(width: 198, height: 242)

        XCTAssertEqual(regular.hourlyHistogramSpacing(forBinCount: 11), 3)
        XCTAssertEqual(regular.hourlyHistogramSpacing(forBinCount: 17), 2)
        XCTAssertEqual(regular.hourlyHistogramSpacing(forBinCount: 24), 1)
    }

    func testWatchRefreshPolicyRefreshesEveryFiveMinutesWhileOpen() {
        XCTAssertEqual(WatchRefreshPolicy.foregroundRefreshIntervalSeconds, 300)
        XCTAssertTrue(WatchRefreshPolicy.refreshesOnAppear)
    }

    func testWatchRefreshPolicyDoesNotWaitForDirectTimeoutBeforePhoneRelay() {
        XCTAssertTrue(WatchRefreshPolicy.requestsPhoneRelayOnOpen)
        XCTAssertLessThanOrEqual(WatchRefreshPolicy.directRefreshTimeoutSeconds, 10)
    }

    func testWatchRefreshPolicyDebouncesDuplicatePhoneRelayRequests() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(WatchRefreshPolicy.shouldRequestPhoneRelay(lastRequestAt: nil, now: now))
        XCTAssertFalse(WatchRefreshPolicy.shouldRequestPhoneRelay(lastRequestAt: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(WatchRefreshPolicy.shouldRequestPhoneRelay(lastRequestAt: now.addingTimeInterval(-3), now: now))
    }

    func testWatchLayoutMetricsScalesQuotaReadoutAcrossWatchFamilies() {
        let compact = WatchLayoutMetrics(width: 162, height: 197)
        let regular = WatchLayoutMetrics(width: 198, height: 242)
        let ultra = WatchLayoutMetrics(width: 205, height: 251)

        XCTAssertEqual(compact.quotaHeadlineFontSize, 31)
        XCTAssertEqual(regular.quotaHeadlineFontSize, 36)
        XCTAssertEqual(ultra.quotaHeadlineFontSize, 40)
    }

    func testWatchLayoutMetricsUsesCompactDualWindowReadout() {
        let compact = WatchLayoutMetrics(width: 162, height: 197)
        let regular = WatchLayoutMetrics(width: 198, height: 242)
        let ultra = WatchLayoutMetrics(width: 205, height: 251)

        XCTAssertEqual(compact.dualWindowQuotaHeadlineFontSize, 24)
        XCTAssertEqual(regular.dualWindowQuotaHeadlineFontSize, 27)
        XCTAssertEqual(ultra.dualWindowQuotaHeadlineFontSize, 30)
        XCTAssertEqual(compact.dualWindowSegmentHeight, 8)
        XCTAssertEqual(regular.dualWindowSegmentHeight, 9)
        XCTAssertEqual(ultra.dualWindowSegmentHeight, 10)
    }

    func testUsageClientTimeoutKeepsInteractiveFetchBounded() {
        XCTAssertEqual(UsageClient.watchRequestTimeoutSeconds, 20)
    }

    func testUsageClientAddsForceRefreshToWatchURLByDefault() throws {
        let defaultURL = try XCTUnwrap(UsageClient.watchURL(macAgentBaseURL: "http://mac.local:8788"))
        let cachedURL = try XCTUnwrap(UsageClient.watchURL(macAgentBaseURL: "http://mac.local:8788", forceRefresh: false))

        XCTAssertEqual(defaultURL.absoluteString, "http://mac.local:8788/watch?force=1")
        XCTAssertEqual(cachedURL.absoluteString, "http://mac.local:8788/watch")
    }

    func testWidgetSummaryUsesLatestCodexSnapshotWithoutNetworkState() {
        var codex = ProviderUsage.placeholder(status: "ok")
        codex.todayTokens = 1_260_000
        codex.todayInputTokens = 100_000
        codex.todayOutputTokens = 50_000
        codex.todayCacheTokens = 1_100_000
        codex.quotaUpdatedAt = "2026-06-12T11:58:00Z"
        codex.buckets = [
            QuotaBucket(
                id: "codex:primary",
                label: "codex 5h",
                remainingPercent: 64,
                usedPercent: 36,
                resetIn: "3h 58m",
                window: "5h",
                status: "ok"
            ),
            QuotaBucket(
                id: "codex:secondary",
                label: "codex 7d",
                remainingPercent: 9,
                usedPercent: 91,
                resetIn: "2d 15h",
                window: "7d",
                status: "ok"
            ),
        ]
        let snapshot = WatchSnapshot(updatedAt: "2026-06-12T12:00:00Z", codex: codex)
        let summary = WidgetQuotaSummary(snapshot: snapshot, timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.fiveHour.percentLabel, "64%")
        XCTAssertEqual(summary.fiveHour.refillLabel, "↻ 15:58 回满")
        XCTAssertEqual(summary.fiveHour.progress, 0.64, accuracy: 0.001)
        XCTAssertEqual(summary.sevenDay?.percentLabel, "9%")
        XCTAssertEqual(summary.sevenDay?.refillLabel, "↻ 06/15 03:00 回满")
        XCTAssertEqual(summary.sevenDay?.tone, .critical)
        XCTAssertEqual(summary.updatedLabel, "刷新 11:58")
        XCTAssertEqual(summary.modelLabel, "GPT-5.5")
        XCTAssertEqual(summary.todayLabel, "今日 1.3M")
        XCTAssertEqual(summary.tokenBreakdownLabel, "In 100.0K · Out 50.0K · Cache 1.1M")
    }

    func testWidgetSummaryShowsSetupWhenSnapshotIsMissing() {
        let summary = WidgetQuotaSummary(snapshot: nil, timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertEqual(summary.status, .setup)
        XCTAssertEqual(summary.title, "Codex Quota")
        XCTAssertEqual(summary.fiveHour.percentLabel, "--%")
        XCTAssertEqual(summary.fiveHour.refillLabel, "↻ --")
        XCTAssertEqual(summary.updatedLabel, "等待同步")
    }

    func testPairingPayloadParsesValidPairingURI() throws {
        let payload = try PairingPayload.parse(
            "llmquota://pair?url=http%3A%2F%2Fmac.local%3A8787&token=abc1234567890_ABCDEF123456"
        )

        XCTAssertEqual(payload.macURL, "http://mac.local:8787")
        XCTAssertEqual(payload.token, "abc1234567890_ABCDEF123456")
    }

    func testPairingPayloadRejectsUnsafeOrIncompleteURI() {
        XCTAssertThrowsError(try PairingPayload.parse("https://example.com/pair?token=abc1234567890_ABCDEF123456"))
        XCTAssertThrowsError(try PairingPayload.parse("llmquota://pair?url=file%3A%2F%2Ftmp%2Fagent&token=abc1234567890_ABCDEF123456"))
        XCTAssertThrowsError(try PairingPayload.parse("llmquota://pair?url=http%3A%2F%2Fmac.local%3A8787&token=short"))
    }

    func testWatchTokenSanitizesWhitespaceAndRejectsInvalidValues() {
        XCTAssertEqual(WatchToken.sanitize("  abc1234567890_ABCDEF123456\n"), "abc1234567890_ABCDEF123456")
        XCTAssertNil(WatchToken.sanitize(""))
        XCTAssertNil(WatchToken.sanitize("abc1234567890"))
        XCTAssertNil(WatchToken.sanitize("abc1234567890_ABCDEF123456!"))
    }

    func testDiagnosticsTextClassifiesMacURLAndToken() {
        XCTAssertEqual(DiagnosticsText.macURLStatus("http://mac.local:8787"), "configured")
        XCTAssertEqual(DiagnosticsText.macURLStatus("https://quota.tailnet.ts.net"), "configured")
        XCTAssertEqual(DiagnosticsText.macURLStatus("127.0.0.1:8787"), "invalid")
        XCTAssertEqual(DiagnosticsText.macURLStatus("file:///tmp/agent"), "invalid")

        XCTAssertEqual(DiagnosticsText.tokenStatus("abc1234567890_ABCDEF123456"), "configured")
        XCTAssertEqual(DiagnosticsText.tokenStatus("short"), "missing/invalid")
    }

    func testRefreshRequestPayloadIsDurableAndRecognizable() {
        let requestedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let payload = RefreshRequestPayload.make(reason: "watch-opened", requestedAt: requestedAt)

        XCTAssertTrue(RefreshRequestPayload.isRefreshRequest(payload))
        XCTAssertEqual(payload[AppConstants.refreshRequestKey] as? Bool, true)
        XCTAssertEqual(payload[RefreshRequestPayload.reasonKey] as? String, "watch-opened")
        XCTAssertEqual(payload[RefreshRequestPayload.requestedAtKey] as? TimeInterval, requestedAt.timeIntervalSince1970)
        XCTAssertFalse(RefreshRequestPayload.isRefreshRequest(["other": true]))
    }
}
