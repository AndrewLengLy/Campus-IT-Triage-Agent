/**
 * Append-only audit logging and SLA calculation for Campus IT triage actions.
 * Writes run in system mode so a missing field permission cannot drop the trail.
 * Logging never throws into the student-facing path.
 */
public with sharing class ITDeskAuditService {
    public static final String ACTION_SELF_SERVICE = 'Self_Service';
    public static final String ACTION_ESCALATE = 'Escalate';
    public static final String ACTION_UPDATE = 'Update';
    public static final String ACTION_STATUS = 'Status';
    public static final String ACTION_OPERATIONS = 'Operations';

    public static final String OUTCOME_MATCHED = 'Matched';
    public static final String OUTCOME_NO_MATCH = 'No_Match';
    public static final String OUTCOME_CREATED = 'Created';
    public static final String OUTCOME_REUSED = 'Reused';
    public static final String OUTCOME_UPDATED = 'Updated';
    public static final String OUTCOME_FOUND = 'Found';
    public static final String OUTCOME_NOT_FOUND = 'Not_Found';
    public static final String OUTCOME_FAILED = 'Failed';
    public static final String OUTCOME_SNAPSHOT = 'Snapshot';

    private static final Integer DEFAULT_SLA_HOURS = 16;

    @TestVisible
    private static List<IT_SLA_Rule__mdt> slaOverrides;

    public static Campus_IT_Interaction__c newInteraction(
        String actionType,
        String outcome,
        Boolean success,
        String studentId,
        Id caseId,
        String caseNumber,
        String category,
        String articleTitle,
        String summary
    ) {
        Campus_IT_Interaction__c row = new Campus_IT_Interaction__c();
        row.Action_Type__c = actionType;
        row.Outcome__c = outcome;
        row.Success__c = success == true;
        row.Student_ID__c = clip(ITDeskRoutingService.normalizeStudentId(studentId), 40);
        row.Case__c = caseId;
        row.Case_Number__c = clip(caseNumber, 40);
        row.Category__c = clip(category, 40);
        row.Article_Title__c = clip(articleTitle, 80);
        row.Summary__c = clip(summary, 32768);
        return row;
    }

    public static void log(List<Campus_IT_Interaction__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        try {
            List<Campus_IT_Interaction__c> toInsert = new List<Campus_IT_Interaction__c>();
            for (Campus_IT_Interaction__c row : rows) {
                if (row != null && String.isNotBlank(row.Action_Type__c) && String.isNotBlank(row.Outcome__c)) {
                    toInsert.add(row);
                }
            }
            if (toInsert.isEmpty()) {
                return;
            }
            Writer.insertRows(toInsert);
        } catch (Exception ignored) {
            // Student-facing actions must not fail because audit logging failed.
        }
    }

    private without sharing class Writer {
        public static void insertRows(List<Campus_IT_Interaction__c> rows) {
            Database.insert(rows, false);
        }
    }

    public static Datetime firstResponseDue(String priority) {
        Integer hours = DEFAULT_SLA_HOURS;
        String key = String.isBlank(priority) ? ITDeskRoutingService.PRIORITY_MEDIUM : priority.trim();
        for (IT_SLA_Rule__mdt rule : slaRows()) {
            if (rule != null && key.equalsIgnoreCase(rule.Priority__c) && rule.First_Response_Hours__c != null) {
                hours = rule.First_Response_Hours__c.intValue();
                break;
            }
        }
        return Datetime.now().addHours(hours);
    }

    private static String clip(String value, Integer maxLen) {
        if (String.isBlank(value) || maxLen == null || maxLen <= 0) {
            return value;
        }
        String trimmed = value.trim();
        return trimmed.length() > maxLen ? trimmed.substring(0, maxLen) : trimmed;
    }

    private static List<IT_SLA_Rule__mdt> slaRows() {
        if (slaOverrides != null) {
            return slaOverrides;
        }
        return IT_SLA_Rule__mdt.getAll().values();
    }
}
