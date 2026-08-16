/**
 * Agentforce-callable action that looks up an existing Campus IT Case
 * by Case Number or Student ID so the agent can report status in-chat.
 */
public with sharing class ITDeskTicketStatus {
    /**
     * Provide Case Number when the student has a ticket number.
     * Provide Student ID to find their most recently updated Case.
     */
    public class StatusRequest {
        @InvocableVariable(
            label='Case Number'
            description='Service Cloud Case Number, for example 00001234. Prefer this when the student already has a ticket number. Wins over Student ID when both are provided.'
        )
        public String caseNumber;

        @InvocableVariable(
            label='Student ID'
            description='Campus student identifier used when the student does not know their ticket number. Returns the most recently updated Case for that student, preferring open tickets.'
        )
        public String studentId;
    }

    public class StatusResult {
        @InvocableVariable(
            label='Success Status'
            description='True when a matching Case was found. If false, follow Next Steps before creating a new ticket.'
        )
        public Boolean isSuccess;

        @InvocableVariable(label='Case Number' description='Case Number to read back to the student.')
        public String caseNumber;

        @InvocableVariable(label='Case ID' description='Salesforce record Id of the Case.')
        public Id caseId;

        @InvocableVariable(label='Status' description='Current Case Status, for example New, Working, or Closed.')
        public String status;

        @InvocableVariable(label='Priority' description='Current Case Priority.')
        public String priority;

        @InvocableVariable(
            label='Queue Name'
            description='Name of the assigned queue, or the owner name when the Case is not on a queue.'
        )
        public String queueName;

        @InvocableVariable(label='Student ID' description='Student ID stored on the Case.')
        public String studentId;

        @InvocableVariable(label='IT Category' description='Canonical category on the Case, for example Network or Hardware.')
        public String category;

        @InvocableVariable(label='Is Closed' description='True when the Case is closed.')
        public Boolean isClosed;

        @InvocableVariable(
            label='Open Ticket Count'
            description='Number of open Cases found for this student when the lookup was by Student ID. 1 when looked up by Case Number.'
        )
        public Integer openTicketCount;

        @InvocableVariable(label='Message' description='Student-facing status sentence to say aloud.')
        public String message;

        @InvocableVariable(label='Next Steps' description='What you should tell the student next.')
        public String nextSteps;
    }

    @InvocableMethod(
        label='Check Campus IT Ticket Status'
        description='Looks up an existing Campus IT Case by Case Number or Student ID and returns status, priority, category, and the assigned queue. Case Number may be spoken as 1234 or 00001234. If Case Number is wrong but Student ID is present, fall back to the student\'s latest ticket. Use when a student asks about an existing ticket. Do not use this to create a new ticket.'
        category='Campus IT'
    )
    public static List<StatusResult> checkStatus(List<StatusRequest> requests) {
        List<StatusResult> results = new List<StatusResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        results = new StatusResult[requests.size()];
        List<PendingLookup> lookups = new List<PendingLookup>();
        Set<String> caseNumbers = new Set<String>();
        Set<String> studentIds = new Set<String>();

        for (Integer i = 0; i < requests.size(); i++) {
            StatusRequest request = requests[i];
            if (request == null || (String.isBlank(request.caseNumber) && String.isBlank(request.studentId))) {
                results[i] = buildValidationFailure();
                continue;
            }

            PendingLookup lookup = new PendingLookup();
            lookup.index = i;
            lookup.caseNumber = String.isBlank(request.caseNumber) ? null : request.caseNumber.trim();
            lookup.studentId = ITDeskRoutingService.normalizeStudentId(request.studentId);
            lookups.add(lookup);
            if (lookup.caseNumber != null) {
                caseNumbers.add(lookup.caseNumber);
            }
            if (lookup.studentId != null) {
                studentIds.add(lookup.studentId);
            }
        }

        if (lookups.isEmpty()) {
            logStatusChecks(requests, results);
            return results;
        }

        Map<String, Case> casesByNumber = ITDeskRoutingService.queryCasesByNumber(caseNumbers);
        Map<String, List<Case>> casesByStudentId = ITDeskRoutingService.queryCasesByStudentId(studentIds);
        Map<Id, Group> queuesById = collectOwnerQueues(casesByNumber.values(), casesByStudentId);

        for (PendingLookup lookup : lookups) {
            List<Case> matches = new List<Case>();
            Case byNumber = ITDeskRoutingService.findCaseByNumber(casesByNumber, lookup.caseNumber);
            if (byNumber != null) {
                matches.add(byNumber);
            } else if (lookup.studentId != null) {
                List<Case> forStudent = ITDeskRoutingService.casesForStudent(casesByStudentId, lookup.studentId);
                if (forStudent != null) {
                    matches.addAll(forStudent);
                }
            }

            if (matches.isEmpty()) {
                results[lookup.index] = buildNotFound(lookup);
                continue;
            }

            Case primary = matches[0];
            Integer openCount = countOpen(matches);
            if (lookup.caseNumber != null) {
                openCount = primary.IsClosed ? 0 : 1;
            }
            results[lookup.index] = buildSuccess(primary, queuesById.get(primary.OwnerId), openCount);
        }

        logStatusChecks(requests, results);
        return results;
    }

    private class PendingLookup {
        Integer index;
        String caseNumber;
        String studentId;
    }

    private static StatusResult buildValidationFailure() {
        StatusResult result = new StatusResult();
        result.isSuccess = false;
        result.openTicketCount = 0;
        result.message = 'I need a case number or a student ID to look up a ticket.';
        result.nextSteps = 'Ask the student for their ticket number or campus Student ID, then retry this action.';
        return result;
    }

    private static StatusResult buildNotFound(PendingLookup lookup) {
        StatusResult result = new StatusResult();
        result.isSuccess = false;
        result.openTicketCount = 0;
        result.studentId = lookup.studentId;
        result.caseNumber = lookup.caseNumber;
        if (lookup.caseNumber != null) {
            result.message = 'I could not find a ticket with that case number.';
            result.nextSteps = 'Confirm the Case Number with the student, or look up by Student ID. If nothing exists, offer to escalate a new ticket.';
        } else {
            result.message = 'I could not find an existing ticket for that student ID.';
            result.nextSteps = 'Confirm the Student ID. If they still need help, escalate a new Campus IT ticket.';
        }
        return result;
    }

    private static StatusResult buildSuccess(Case ticket, Group queue, Integer openCount) {
        StatusResult result = new StatusResult();
        result.isSuccess = true;
        result.caseId = ticket.Id;
        result.caseNumber = ticket.CaseNumber;
        result.status = ticket.Status;
        result.priority = ticket.Priority;
        result.studentId = ticket.Student_ID__c;
        result.category = ticket.IT_Category__c;
        result.isClosed = ticket.IsClosed;
        result.openTicketCount = openCount;
        result.queueName = queue != null ? queue.Name : ticket.Owner.Name;

        String ownerLabel = String.isBlank(result.queueName) ? 'the service desk' : result.queueName;
        result.message =
            'Ticket #' +
            ticket.CaseNumber +
            ' is ' +
            ticket.Status +
            ' with ' +
            ticket.Priority +
            ' priority, assigned to ' +
            ownerLabel +
            '.';

        if (ticket.IsClosed) {
            result.nextSteps = 'The ticket is closed. If the student still has the problem, offer to escalate a new Case.';
        } else {
            result.nextSteps =
                'Share Case Number ' +
                ticket.CaseNumber +
                ' and the current status. A technician on ' +
                ownerLabel +
                ' still owns the work.';
        }
        return result;
    }

    private static Map<Id, Group> collectOwnerQueues(List<Case> numbered, Map<String, List<Case>> byStudent) {
        Set<Id> ownerIds = new Set<Id>();
        for (Case ticket : numbered) {
            ownerIds.add(ticket.OwnerId);
        }
        for (List<Case> tickets : byStudent.values()) {
            for (Case ticket : tickets) {
                ownerIds.add(ticket.OwnerId);
            }
        }
        return ITDeskRoutingService.queryQueuesById(ownerIds);
    }

    private static Integer countOpen(List<Case> tickets) {
        Integer openCount = 0;
        for (Case ticket : tickets) {
            if (!ticket.IsClosed) {
                openCount++;
            }
        }
        return openCount;
    }

    private static void logStatusChecks(List<StatusRequest> requests, List<StatusResult> results) {
        List<Campus_IT_Interaction__c> rows = new List<Campus_IT_Interaction__c>();
        for (Integer i = 0; i < results.size(); i++) {
            StatusResult result = results[i];
            if (result == null) {
                continue;
            }
            StatusRequest request = i < requests.size() ? requests[i] : null;
            String outcome = ITDeskAuditService.OUTCOME_FAILED;
            if (result.isSuccess == true) {
                outcome = ITDeskAuditService.OUTCOME_FOUND;
            } else if (result.message != null && result.message.contains('could not find')) {
                outcome = ITDeskAuditService.OUTCOME_NOT_FOUND;
            }
            rows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_STATUS,
                    outcome,
                    result.isSuccess,
                    request == null ? null : request.studentId,
                    result.caseId,
                    result.caseNumber,
                    result.category,
                    null,
                    result.message
                )
            );
        }
        ITDeskAuditService.log(rows);
    }
}
