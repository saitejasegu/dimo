package app.dimo.android.data.db

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import app.dimo.android.data.model.EmailMessageEntity
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.StoredEntity

/**
 * Synced `emailMessage` entity row — the cloud-visible half of a reviewed
 * suggestion, port of `SyncedEmailMessageRecord` in
 * `ios-native/Dimo/Data/Database/Records.swift`.
 *
 * This is deliberately separate from the device-local `emailMessages` table in
 * [EmailMessageRecord]: only reviewed states are dual-written here, and only this
 * table participates in pull/push. The local table additionally holds queued,
 * failed and expired rows that never leave the device.
 */
@Entity(
  tableName = "syncedEmailMessages",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class SyncedEmailMessageRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val accountId: String,
  val accountEmail: String,
  val gmailMessageId: String,
  val threadId: String,
  val rfcMessageId: String?,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBodyText: String?,
  val analyzerType: String?,
  val modelVersion: String?,
  val promptVersion: Int?,
  val classification: String?,
  val merchant: String?,
  val amount: String?,
  val currency: String?,
  val occurredAt: Long?,
  val categoryId: String?,
  val paymentMethodId: String?,
  val paymentLastFour: String?,
  val reference: String?,
  val state: String,
  val purchaseGroupId: String?,
  val linkedTransactionId: String?,
  val analyzedAt: Long?,
  val reviewedAt: Long?,
  val createdAt: Long,
  val updatedAt: Long,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.EMAIL_MESSAGE,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.EmailMessage(
      EmailMessageEntity(
        id = entityId,
        accountId = accountId,
        accountEmail = accountEmail,
        gmailMessageId = gmailMessageId,
        threadId = threadId,
        rfcMessageId = rfcMessageId,
        senderName = senderName,
        senderAddress = senderAddress,
        subject = subject,
        snippet = snippet,
        internalDate = internalDate,
        normalizedBodyText = normalizedBodyText,
        analyzerType = analyzerType,
        modelVersion = modelVersion,
        promptVersion = promptVersion,
        classification = classification,
        merchant = merchant,
        amount = amount,
        currency = currency,
        occurredAt = occurredAt,
        categoryId = categoryId,
        paymentMethodId = paymentMethodId,
        paymentLastFour = paymentLastFour,
        reference = reference,
        state = state,
        purchaseGroupId = purchaseGroupId,
        linkedTransactionId = linkedTransactionId,
        analyzedAt = analyzedAt,
        reviewedAt = reviewedAt,
        createdAt = createdAt,
        updatedAt = updatedAt,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): SyncedEmailMessageRecord {
      val e = (entity.payload as EntityPayload.EmailMessage).value
      return SyncedEmailMessageRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        accountId = e.accountId,
        accountEmail = e.accountEmail,
        gmailMessageId = e.gmailMessageId,
        threadId = e.threadId,
        rfcMessageId = e.rfcMessageId,
        senderName = e.senderName,
        senderAddress = e.senderAddress,
        subject = e.subject,
        snippet = e.snippet,
        internalDate = e.internalDate,
        normalizedBodyText = e.normalizedBodyText,
        analyzerType = e.analyzerType,
        modelVersion = e.modelVersion,
        promptVersion = e.promptVersion,
        classification = e.classification,
        merchant = e.merchant,
        amount = e.amount,
        currency = e.currency,
        occurredAt = e.occurredAt,
        categoryId = e.categoryId,
        paymentMethodId = e.paymentMethodId,
        paymentLastFour = e.paymentLastFour,
        reference = e.reference,
        state = e.state,
        purchaseGroupId = e.purchaseGroupId,
        linkedTransactionId = e.linkedTransactionId,
        analyzedAt = e.analyzedAt,
        reviewedAt = e.reviewedAt,
        createdAt = e.createdAt,
        updatedAt = e.updatedAt,
      )
    }
  }
}
