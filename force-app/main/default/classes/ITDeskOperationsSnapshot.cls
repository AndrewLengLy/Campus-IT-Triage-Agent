/**
 * Invocable action that reports live Campus IT desk load: open tickets, oldest wait,
 * high-priority volume, and today's self-service deflection. Intended for supervisors
 * and for any caller answering "how backed up is the desk right now?".
 */
public with sharing class ITDeskOperationsSnapshot {
    public class SnapshotRequest {
        @InvocableVariable(
            label='Queue Name'
            description='Optional queue name filter, for example Campus IT - Network. Leave blank for the whole desk.'
        )
        public String queueName;
    }

    public class SnapshotResult {
        @InvocableVariable(label='Open Ticket Count' description='Open Cases created by Campus IT triage, optionally filtered by queue.')
        public Integer openTicketCount;

        @InvocableVariable(label='High Priority Open' description='Open High-priority triage-sourced Cases.')
        public Integer highPriorityOpen;

        @InvocableVariable(label='Oldest Case Number' description='Case Number of the oldest open triage-sourced ticket.')
        public String oldestCaseNumber;

        @InvocableVariable(label='Oldest Wait Hours' description='Whole hours the oldest open triage-sourced ticket has been waiting.')
        public Integer oldestWaitHours;

        @InvocableVariable(label='Self Service Matches Today' description='Known-issue matches logged today.')
        public Integer selfServiceMatchesToday;

        @InvocableVariable(label='Escalations Today' description='New tickets triage created today.')
        public Integer escalationsToday;

        @InvocableVariable(label='Deflection Rate' description='Self-service matches as a percent of matches plus new escalations today. Null when there is no volume.')
        public Decimal deflectionRate;

        @InvocableVariable(label='Queue Breakdown' description='Open ticket counts by assigned queue or owner.')
        public String queueBreakdown;

        @InvocableVariable(label='Message' description='Spoken operations summary.')
        public String message;

        @InvocableVariable(label='Next Steps' description='How to use the snapshot with the student or a supervisor.')
        public String nextSteps;
    }

    @InvocableMethod(
        label='Get Campus IT Operations Snapshot'
        description='Returns current Campus IT desk load: open triage-sourced tickets, oldest wait, high-priority volume, and today\'s self-service deflection rate. Use when a supervisor asks how the desk is doing, or when a student asks whether the service desk is backed up. Do not use this to create or update a ticket.'
        category='Campus IT'
    )
    public static List<SnapshotResult> getSnapshot(List<SnapshotRequest> requests) {
        List<SnapshotResult> results = new List<SnapshotResult>();
        if (requests == null || requests.isEmpty()) {
            requests = new List<SnapshotRequest>{ new SnapshotRequest() };
        }

        Map<Id, Group> campusQueues = loadCampusQueues();
        List<Case> openTickets = [
            SELECT Id, CaseNumber, Priority, CreatedDate, OwnerId, IT_Category__c
            FROM Case
            WHERE IsClosed = FALSE AND Agent_Sourced__c = TRUE
            ORDER BY CreatedDate ASC
        ];

        Integer matchesToday = [
            SELECT COUNT()
            FROM Campus_IT_Interaction__c
            WHERE Action_Type__c = :ITDeskAuditService.ACTION_SELF_SERVICE
            AND Outcome__c = :ITDeskAuditService.OUTCOME_MATCHED
            AND CreatedDate = TODAY
        ];
        Integer createdToday = [
            SELECT COUNT()
            FROM Campus_IT_Interaction__c
            WHERE Action_Type__c = :ITDeskAuditService.ACTION_ESCALATE
            AND Outcome__c = :ITDeskAuditService.OUTCOME_CREATED
            AND CreatedDate = TODAY
        ];

        List<Campus_IT_Interaction__c> auditRows = new List<Campus_IT_Interaction__c>();
        for (SnapshotRequest request : requests) {
            if (request == null) {
                request = new SnapshotRequest();
            }
            SnapshotResult result = buildSnapshot(request, openTickets, campusQueues, matchesToday, createdToday);
            results.add(result);
            auditRows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_OPERATIONS,
                    ITDeskAuditService.OUTCOME_SNAPSHOT,
                    true,
                    null,
                    null,
                    result.oldestCaseNumber,
                    request.queueName,
                    null,
                    result.message
                )
            );
        }
        ITDeskAuditService.log(auditRows);
        return results;
    }

    private static SnapshotResult buildSnapshot(
        SnapshotRequest request,
        List<Case> openTickets,
        Map<Id, Group> campusQueues,
        Integer matchesToday,
        Integer createdToday
    ) {
        String filter = String.isBlank(request.queueName) ? null : request.queueName.trim().toLowerCase();
        List<Case> scoped = new List<Case>();
        Map<String, Integer> byQueue = new Map<String, Integer>();
        Integer highPriority = 0;

        for (Case ticket : openTickets) {
            String ownerLabel = ownerLabel(ticket.OwnerId, campusQueues);
            if (filter != null && !ownerLabel.toLowerCase().contains(filter)) {
                continue;
            }
            scoped.add(ticket);
            Integer current = byQueue.containsKey(ownerLabel) ? byQueue.get(ownerLabel) : 0;
            byQueue.put(ownerLabel, current + 1);
            if (ticket.Priority == ITDeskRoutingService.PRIORITY_HIGH) {
                highPriority++;
            }
        }

        SnapshotResult result = new SnapshotResult();
        result.openTicketCount = scoped.size();
        result.highPriorityOpen = highPriority;
        result.selfServiceMatchesToday = matchesToday;
        result.escalationsToday = createdToday;
        result.queueBreakdown = formatBreakdown(byQueue);

        Integer volume = matchesToday + createdToday;
        if (volume > 0) {
            result.deflectionRate = ((Decimal) matchesToday / (Decimal) volume * 100).setScale(1);
        }

        if (!scoped.isEmpty()) {
            Case oldest = scoped[0];
            result.oldestCaseNumber = oldest.CaseNumber;
            Long millis = Datetime.now().getTime() - oldest.CreatedDate.getTime();
            result.oldestWaitHours = Integer.valueOf(millis / (1000L * 60L * 60L));
        }

        result.message = buildMessage(result, filter);
        result.nextSteps = 'Share the open count and oldest wait if asked. Do not promise a technician arrival time.';
        return result;
    }

    private static String buildMessage(SnapshotResult result, String filter) {
        String scope = filter == null ? 'Campus IT' : filter;
        String wait = result.oldestCaseNumber == null
            ? 'No triage-sourced tickets are waiting.'
            : 'Oldest ticket is #' +
                result.oldestCaseNumber +
                ', waiting about ' +
                result.oldestWaitHours +
                ' hours.';
        String deflection = result.deflectionRate == null
            ? 'No deflection data yet today.'
            : 'Today\'s self-service deflection is ' + result.deflectionRate + ' percent.';
        return scope +
            ' has ' +
            result.openTicketCount +
            ' open triage-sourced tickets (' +
            result.highPriorityOpen +
            ' high priority). ' +
            wait +
            ' ' +
            deflection;
    }

    private static Map<Id, Group> loadCampusQueues() {
        return new Map<Id, Group>([
            SELECT Id, Name, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName LIKE 'Campus_IT_%'
        ]);
    }

    private static String ownerLabel(Id ownerId, Map<Id, Group> campusQueues) {
        Group queue = campusQueues.get(ownerId);
        return queue != null ? queue.Name : 'Unassigned / other';
    }

    private static String formatBreakdown(Map<String, Integer> byQueue) {
        if (byQueue.isEmpty()) {
            return 'None';
        }
        List<String> parts = new List<String>();
        List<String> names = new List<String>(byQueue.keySet());
        names.sort();
        for (String name : names) {
            parts.add(name + ': ' + byQueue.get(name));
        }
        return String.join(parts, '; ');
    }
}
