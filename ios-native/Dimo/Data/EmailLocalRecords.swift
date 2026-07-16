import Foundation
import GRDB

struct EmailAccountRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "emailAccounts"

  var id: String
  var emailAddress: String
  var historyId: String?
  var backfillPageToken: String?
  var backfillCompletedAt: Int?
  var lastAttemptAt: Int?
  var lastSuccessfulSyncAt: Int?
  var syncState: String
  var lastError: String?
  var createdAt: Int
  var updatedAt: Int

  func toModel() throws -> EmailAccountRecordModel {
    guard let state = EmailAccountSyncState(rawValue: syncState) else {
      throw EmailRepositoryError.invalidAccount
    }
    return EmailAccountRecordModel(
      id: id,
      emailAddress: emailAddress,
      historyId: historyId,
      backfillPageToken: backfillPageToken,
      backfillCompletedAt: backfillCompletedAt,
      lastAttemptAt: lastAttemptAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt,
      syncState: state,
      lastError: lastError,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  static func from(_ account: EmailAccountRecordModel) -> EmailAccountRecord {
    EmailAccountRecord(
      id: account.id,
      emailAddress: account.emailAddress,
      historyId: account.historyId,
      backfillPageToken: account.backfillPageToken,
      backfillCompletedAt: account.backfillCompletedAt,
      lastAttemptAt: account.lastAttemptAt,
      lastSuccessfulSyncAt: account.lastSuccessfulSyncAt,
      syncState: account.syncState.rawValue,
      lastError: account.lastError,
      createdAt: account.createdAt,
      updatedAt: account.updatedAt
    )
  }
}

struct EmailMessageRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "emailMessages"

  var key: String
  var accountId: String
  var gmailMessageId: String
  var threadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var normalizedBodyText: String?
  var analysisProviderOverride: String?
  var analyzerType: String?
  var modelVersion: String?
  var promptVersion: Int?
  var classification: String?
  var merchant: String?
  var amount: String?
  var currency: String?
  var occurredAt: Int?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
  var state: String
  var linkedTransactionId: String?
  var analyzedAt: Int?
  var reviewedAt: Int?
  var createdAt: Int
  var updatedAt: Int

  func toModel() throws -> EmailMessageRecordModel {
    guard let decodedState = EmailSuggestionState(rawValue: state) else {
      throw EmailRepositoryError.invalidSuggestionState
    }
    let decodedAnalyzer = try analyzerType.map { value in
      guard let analyzer = EmailAnalyzerKind(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return analyzer
    }
    let decodedProviderOverride = try analysisProviderOverride.map { value in
      guard let provider = EmailAnalysisProvider(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return provider
    }
    let decodedClassification = try classification.map { value in
      guard let classification = EmailMessageClassification(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return classification
    }
    let decodedCurrency = try currency.map { value in
      guard let currency = Currency(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return currency
    }
    return EmailMessageRecordModel(
      key: key,
      accountId: accountId,
      gmailMessageId: gmailMessageId,
      threadId: threadId,
      rfcMessageId: rfcMessageId,
      senderName: senderName,
      senderAddress: senderAddress,
      subject: subject,
      snippet: snippet,
      internalDate: internalDate,
      normalizedBodyText: normalizedBodyText,
      analysisProviderOverride: decodedProviderOverride,
      analyzerType: decodedAnalyzer,
      modelVersion: modelVersion,
      promptVersion: promptVersion,
      classification: decodedClassification,
      merchant: merchant,
      amount: amount,
      currency: decodedCurrency,
      occurredAt: occurredAt,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      paymentLastFour: paymentLastFour,
      reference: reference,
      state: decodedState,
      linkedTransactionId: linkedTransactionId,
      analyzedAt: analyzedAt,
      reviewedAt: reviewedAt,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  static func pending(_ message: PendingEmailMessage, now: Int) -> EmailMessageRecord {
    EmailMessageRecord(
      key: message.key,
      accountId: message.accountId,
      gmailMessageId: message.gmailMessageId,
      threadId: message.threadId,
      rfcMessageId: message.rfcMessageId,
      senderName: message.senderName,
      senderAddress: message.senderAddress,
      subject: message.subject,
      snippet: message.snippet,
      internalDate: message.internalDate,
      normalizedBodyText: message.normalizedBodyText,
      analysisProviderOverride: nil,
      analyzerType: nil,
      modelVersion: nil,
      promptVersion: nil,
      classification: nil,
      merchant: nil,
      amount: nil,
      currency: nil,
      occurredAt: nil,
      categoryId: nil,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil,
      state: EmailSuggestionState.pendingAnalysis.rawValue,
      linkedTransactionId: nil,
      analyzedAt: nil,
      reviewedAt: nil,
      createdAt: now,
      updatedAt: now
    )
  }
}

struct EmailAnalysisSettingsRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "emailAnalysisSettings"

  var id: String
  var selectedProvider: String?
  var openRouterModelID: String?
  var openRouterPrivacyMode: String
  var nonZDRConsentVersion: Int?
  var syncWindow: String
  var updatedAt: Int

  func toModel() throws -> EmailAnalysisSettings {
    let provider = try selectedProvider.map { rawValue in
      guard let value = EmailAnalysisProvider(rawValue: rawValue) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return value
    }
    guard let privacyMode = OpenRouterPrivacyMode(rawValue: openRouterPrivacyMode) else {
      throw EmailRepositoryError.invalidAnalysis
    }
    guard let syncWindow = EmailSyncWindow(rawValue: syncWindow) else {
      throw EmailRepositoryError.invalidAnalysis
    }
    return EmailAnalysisSettings(
      selectedProvider: provider,
      openRouterModelID: openRouterModelID,
      openRouterPrivacyMode: privacyMode,
      nonZDRConsentVersion: nonZDRConsentVersion,
      syncWindow: syncWindow,
      updatedAt: updatedAt
    )
  }

  static func from(_ value: EmailAnalysisSettings) -> EmailAnalysisSettingsRecord {
    EmailAnalysisSettingsRecord(
      id: EmailAnalysisSettings.singletonID,
      selectedProvider: value.selectedProvider?.rawValue,
      openRouterModelID: value.openRouterModelID,
      openRouterPrivacyMode: value.openRouterPrivacyMode.rawValue,
      nonZDRConsentVersion: value.nonZDRConsentVersion,
      syncWindow: value.syncWindow.rawValue,
      updatedAt: value.updatedAt
    )
  }
}

struct EmailAnalysisRetryRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "emailAnalysisRetry"

  var id: String
  var attempt: Int
  var notBefore: Int?
  var reason: String?
  var lastHTTPStatus: Int?
  var updatedAt: Int

  func toModel() -> EmailAnalysisRetryState {
    EmailAnalysisRetryState(
      attempt: attempt,
      notBefore: notBefore,
      reason: reason,
      lastHTTPStatus: lastHTTPStatus,
      updatedAt: updatedAt
    )
  }
}

struct EmailMessageSummaryRecord: Decodable, FetchableRecord {
  var key: String
  var accountId: String
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var analyzerType: String?
  var modelVersion: String?
  var classification: String?
  var state: String
  var analyzedAt: Int?
  var reviewedAt: Int?

  func toModel() throws -> EmailMessageSummaryModel {
    guard let decodedState = EmailSuggestionState(rawValue: state) else {
      throw EmailRepositoryError.invalidSuggestionState
    }
    let decodedAnalyzer = try analyzerType.map { value in
      guard let analyzer = EmailAnalyzerKind(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return analyzer
    }
    let decodedClassification = try classification.map { value in
      guard let classification = EmailMessageClassification(rawValue: value) else {
        throw EmailRepositoryError.invalidAnalysis
      }
      return classification
    }
    return EmailMessageSummaryModel(
      id: key,
      accountId: accountId,
      senderName: senderName,
      senderAddress: senderAddress,
      subject: subject,
      snippet: snippet,
      internalDate: internalDate,
      analyzerType: decodedAnalyzer,
      modelVersion: modelVersion,
      classification: decodedClassification,
      state: decodedState,
      analyzedAt: analyzedAt,
      reviewedAt: reviewedAt
    )
  }
}
