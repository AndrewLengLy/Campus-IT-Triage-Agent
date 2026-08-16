/**
 * Agentforce action that appends a published Case Comment when a student has
 * more information for an existing Campus IT ticket.
 */
public with sharing class ITDeskTicketUpdate {
    public class UpdateRequest {
        @InvocableVariable(
            label='Case Number'
            description='Service Cloud Case Number, for example 00001234. Prefer this when the student already has a ticket number.'
        )
        public String caseNumber;

        @InvocableVariable(
            label='Student ID'
            description='Campus student identifier. Required when Case Number is unknown. When both are provided, the Case must belong to this student.'
        )
        public String studentId;

        @InvocableVariable(
            required=true
            label='Update Details'
            description='New information from the student to add to the ticket, such as error text, what they already tried, or a building and room number.'
        )
        public String updateDetails;
    }

    public class UpdateResult {
        @InvocableVariable(label='Success Status' description='True when a Case Comment was added.')
        public Boolean isSuccess;

        @InvocableVariable(label='Case Number' description='Case Number that received the update.')
        public String caseNumber;

        @InvocableVariable(label='Case ID' description='Salesforce record Id of the Case.')
        public Id caseId;

        @InvocableVariable(label='Message' description='Student-facing confirmation to say aloud.')
        public String message;

        @InvocableVariable(label='Next Steps' description='What you should tell the student after the update.')
        public String nextSteps;
    }

    @InvocableMethod(
        label='Add Campus IT Ticket Update'
        description='Adds a published Case Comment to an existing Campus IT ticket. Use when the student has more detail for an open ticket, already tried self-service steps, or wants to add a building, error message, or screenshot description. Do not use this to create a new ticket.'
        category='Campus IT'
    )
    public static List<UpdateResult> addUpdate(List<UpdateRequest> requests) {
        List<UpdateResult> results = new List<UpdateResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        results = new UpdateResult[requests.size()];
        List<PendingUpdate> pending = new List<PendingUpdate>();
        Set<String> caseNumbers = new Set<String>();
        Set<String> studentIds = new Set<String>();

        for (Integer i = 0; i < requests.size(); i++) {
            UpdateRequest request = requests[i];
            if (
                request == null ||
                String.isBlank(request.updateDetails) ||
                (String.isBlank(request.caseNumber) && String.isBlank(request.studentId))
            ) {
                results[i] = buildValidationFailure();
                continue;
            }

            PendingUpdate item = new PendingUpdate();
            item.index = i;
            item.request = request;
            item.caseNumber = String.isBlank(request.caseNumber) ? null : request.caseNumber.trim();
            item.studentId = ITDeskRoutingService.normalizeStudentId(request.studentId);
            pending.add(item);
            if (item.caseNumber != null) {
                caseNumbers.add(item.caseNumber);
            }
            if (item.studentId != null) {
                studentIds.add(item.studentId);
            }
        }

        if (pending.isEmpty()) {
            logUpdates(requests, results);
            return results;
        }

        Map<String, Case> byNumber = ITDeskRoutingService.queryCasesByNumber(caseNumbers);
        Map<String, List<Case>> openByStudent = ITDeskRoutingService.queryOpenCasesByStudentId(studentIds);
        List<CaseComment> comments = new List<CaseComment>();

        for (PendingUpdate item : pending) {
            Case ticket = resolveCase(item, byNumber, openByStudent);
            if (ticket == null) {
                results[item.index] = buildNotFound(item);
                continue;
            }
            if (item.studentId != null && !ITDeskRoutingService.studentIdsMatch(ticket.Student_ID__c, item.studentId)) {
                results[item.index] = buildMismatch();
                continue;
            }
            if (ticket.IsClosed) {
                results[item.index] = buildClosed(ticket);
                continue;
            }

            comments.add(
                ITDeskRoutingService.newPublishedComment(ticket.Id, buildCommentBody(item.request))
            );
            item.ticket = ticket;
        }

        Database.SaveResult[] saveResults = comments.isEmpty()
            ? new List<Database.SaveResult>()
            : Database.insert(comments, false);

        Integer saveIndex = 0;
        for (PendingUpdate item : pending) {
            if (results[item.index] != null) {
                continue;
            }
            Database.SaveResult saveResult = saveResults[saveIndex];
            saveIndex++;
            if (saveResult.isSuccess()) {
                results[item.index] = buildSuccess(item.ticket);
            } else {
                results[item.index] = buildDmlFailure();
            }
        }

        logUpdates(requests, results);
        return results;
    }

    private class PendingUpdate {
        Integer index;
        UpdateRequest request;
        String caseNumber;
        String studentId;
        Case ticket;
    }

    private static UpdateResult buildValidationFailure() {
        UpdateResult result = new UpdateResult();
        result.isSuccess = false;
        result.message = 'I need ticket details and either a case number or a student ID to add an update.';
        result.nextSteps = 'Ask the student for their Case Number or Student ID and the new information, then retry.';
        return result;
    }

    private static UpdateResult buildNotFound(PendingUpdate item) {
        UpdateResult result = new UpdateResult();
        result.isSuccess = false;
        result.caseNumber = item.caseNumber;
        result.message = 'I could not find an open ticket to update.';
        result.nextSteps = 'Confirm the Case Number or Student ID. If they do not have a ticket yet, escalate a new one.';
        return result;
    }

    private static UpdateResult buildClosed(Case ticket) {
        UpdateResult result = new UpdateResult();
        result.isSuccess = false;
        result.caseId = ticket.Id;
        result.caseNumber = ticket.CaseNumber;
        result.message = 'Ticket #' + ticket.CaseNumber + ' is already closed.';
        result.nextSteps = 'If the student still has the problem, escalate a new Campus IT ticket instead of adding a comment.';
        return result;
    }

    private static UpdateResult buildMismatch() {
        UpdateResult result = new UpdateResult();
        result.isSuccess = false;
        result.message = 'That case number does not match this student ID.';
        result.nextSteps = 'Confirm both values with the student. Do not add a comment to another student\'s ticket.';
        return result;
    }

    private static UpdateResult buildDmlFailure() {
        UpdateResult result = new UpdateResult();
        result.isSuccess = false;
        result.message = 'I found the ticket but could not add the update just now.';
        result.nextSteps = 'Ask the student to retry, or escalate a new note through the walk-up desk.';
        return result;
    }

    private static UpdateResult buildSuccess(Case ticket) {
        UpdateResult result = new UpdateResult();
        result.isSuccess = true;
        result.caseId = ticket.Id;
        result.caseNumber = ticket.CaseNumber;
        result.message = 'I added your update to ticket #' + ticket.CaseNumber + '.';
        result.nextSteps = 'Confirm the Case Number. A technician on the assigned queue will see the new comment.';
        return result;
    }

    private static String buildCommentBody(UpdateRequest request) {
        List<String> lines = new List<String>{
            'Student update via Campus IT Triage Agent',
            '',
            request.updateDetails.trim()
        };
        if (String.isNotBlank(request.studentId)) {
            lines.add('');
            lines.add('Student ID: ' + request.studentId.trim());
        }
        return String.join(lines, '\n');
    }

    private static Case resolveCase(
        PendingUpdate item,
        Map<String, Case> byNumber,
        Map<String, List<Case>> openByStudent
    ) {
        Case byNumberMatch = ITDeskRoutingService.findCaseByNumber(byNumber, item.caseNumber);
        if (byNumberMatch != null) {
            return byNumberMatch;
        }
        if (item.caseNumber == null && item.studentId != null) {
            List<Case> openCases = ITDeskRoutingService.casesForStudent(openByStudent, item.studentId);
            if (openCases != null && !openCases.isEmpty()) {
                return openCases[0];
            }
        }
        return null;
    }

    private static void logUpdates(List<UpdateRequest> requests, List<UpdateResult> results) {
        List<Campus_IT_Interaction__c> rows = new List<Campus_IT_Interaction__c>();
        for (Integer i = 0; i < results.size(); i++) {
            UpdateResult result = results[i];
            if (result == null) {
                continue;
            }
            UpdateRequest request = i < requests.size() ? requests[i] : null;
            String outcome = result.isSuccess == true
                ? ITDeskAuditService.OUTCOME_UPDATED
                : ITDeskAuditService.OUTCOME_FAILED;
            if (result.isSuccess != true && result.message != null && result.message.contains('could not find')) {
                outcome = ITDeskAuditService.OUTCOME_NOT_FOUND;
            }
            rows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_UPDATE,
                    outcome,
                    result.isSuccess,
                    request == null ? null : request.studentId,
                    result.caseId,
                    result.caseNumber,
                    null,
                    null,
                    result.message
                )
            );
        }
        ITDeskAuditService.log(rows);
    }
}
