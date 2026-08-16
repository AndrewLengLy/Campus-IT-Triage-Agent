/**
 * Campus IT Interactions are an append-only audit trail.
 * Updates and deletes are blocked so operations metrics stay trustworthy.
 */
trigger CampusITInteractionGuard on Campus_IT_Interaction__c (before update, before delete) {
    if (Trigger.isUpdate) {
        for (Campus_IT_Interaction__c row : Trigger.new) {
            row.addError('Campus IT Interactions are append-only and cannot be edited.');
        }
        return;
    }
    if (Trigger.isDelete) {
        for (Campus_IT_Interaction__c row : Trigger.old) {
            row.addError('Campus IT Interactions are append-only and cannot be deleted.');
        }
    }
}
