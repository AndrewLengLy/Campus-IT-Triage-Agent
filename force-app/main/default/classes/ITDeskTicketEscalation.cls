/**
 * Agentforce-callable action that escalates a student IT issue to a Service Cloud Case.
 *
 * Atlas binds conversation slots to EscalationRequest fields via @InvocableVariable
 * labels/descriptions. Keep those strings in sync with the custom action in Agent Builder.
 *
 * Queue routing and Contact/open-Case lookups live in ITDeskRoutingService so admins
 * can change category maps in Custom Metadata without a code deploy.
 */
public with sharing class ITDeskTicketEscalation {
    private static final String CASE_ORIGIN_WEB = 'Web';
    private static final String CASE_STATUS_NEW = 'New';
    private static final Integer SUBJECT_DESC_LIMIT = 80;
    private static final Integer SUBJECT_MAX_LENGTH = 255;

    /**
     * Inputs Atlas extracts from the student conversation.
     */
    public class EscalationRequest {
        @InvocableVariable(
            required=true
            label='Student ID'
            description='Campus student identifier (for example S12345678). Required so technicians can locate the student. Ask for it if it has not been provided.'
        )
        public String studentId;

        @InvocableVariable(
            required=true
            label='Issue Description'
            description='Natural-language description of the IT problem. Use the student\'s own wording plus any troubleshooting already attempted.'
        )
        public String issueDescription;

        @InvocableVariable(
            label='Urgency'
            description='How urgent the student says the issue is. Examples: Critical, Emergency, High, Urgent, Medium, Normal, Low, P1, P2, P3, P4. Leave blank if unknown; the Case defaults to Medium priority.'
        )
        public String urgency;

        @InvocableVariable(
            label='Category'
            description='IT category used to route the Case. Examples: Network, WiFi, VPN, Hardware, Laptop, Printer, Software, Email, Outlook, Account, Password, Login, MFA. Unmatched values go to the general Campus IT queue.'
        )
        public String category;

        @InvocableVariable(
            label='Force New Ticket'
            description='Set true only when the student confirms this is a brand-new issue, not an update to an existing open ticket. Leave false or blank to reuse an open Case in the same category.'
        )
        public Boolean forceNewTicket;

        @InvocableVariable(
            label='Student Email'
            description='Optional campus email so technicians can reply. Maps to Case SuppliedEmail. Ask for it if the student offers a contact address.'
        )
        public String studentEmail;

        @InvocableVariable(
            label='Self Service Attempted'
            description='Set true when Find Campus IT Self-Service Guide was already called in this conversation.'
        )
        public Boolean selfServiceAttempted;

        @InvocableVariable(
            label='Self Service Article'
            description='Title of the guide the student already tried, if any.'
        )
        public String selfServiceArticle;
    }

    /**
     * Outputs the agent speaks back to the student.
     */
    public class EscalationResult {
        @InvocableVariable(
            label='Success Status'
            description='True when a Case was created or an existing open ticket was reused. If false, tell the student a ticket was not opened and follow Next Steps.'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Case Number'
            description='Service Cloud Case Number to read back to the student, for example 00001234.'
        )
        public String caseNumber;

        @InvocableVariable(
            label='Case ID'
            description='Salesforce record Id of the Case. Use this if you need to open or update the ticket.'
        )
        public Id caseId;

        @InvocableVariable(
            label='Existing Ticket'
            description='True when an open Case for this student and category was reused instead of creating a duplicate.'
        )
        public Boolean isExistingTicket;

        @InvocableVariable(
            label='Message'
            description='Student-facing confirmation to say aloud, including the ticket number when the action succeeded.'
        )
        public String message;

        @InvocableVariable(
            label='Next Steps'
            description='Guidance for what you should tell the student about follow-up, queue routing, or what to collect before retrying.'
        )
        public String nextSteps;
    }

    /**
     * Creates and queue-routes a Case, or returns an existing open ticket in the same category.
     */
    @InvocableMethod(
        label='Escalate Campus IT Ticket'
        description='Creates a Service Cloud Case when a student IT issue cannot be resolved in-chat. Call Find Campus IT Self-Service Guide first. Reuses an existing open ticket for the same student and category unless Force New Ticket is true. Use when the student needs a human technician, self-service steps failed, or they explicitly ask to escalate. Returns the Case Number so you can confirm the ticket with the student.'
        category='Campus IT'
    )
    public static List<EscalationResult> escalate(List<EscalationRequest> requests) {
        List<EscalationResult> results = new List<EscalationResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        results = new EscalationResult[requests.size()];

        List<PendingInsert> pending = new List<PendingInsert>();
        Set<String> studentIds = new Set<String>();
        Set<String> queueDeveloperNames = new Set<String>();

        for (Integer i = 0; i < requests.size(); i++) {
            EscalationRequest request = requests[i];
            if (!isValid(request)) {
                results[i] = buildValidationFailure();
                continue;
            }

            PendingInsert item = new PendingInsert();
            item.index = i;
            item.request = request;
            item.studentId = ITDeskRoutingService.normalizeStudentId(request.studentId);
            item.queueDeveloperName = ITDeskRoutingService.resolveQueueDeveloperName(request.category);
            pending.add(item);
            studentIds.add(item.studentId);
            queueDeveloperNames.add(item.queueDeveloperName);
        }

        if (pending.isEmpty()) {
            logEscalations(requests, results);
            return results;
        }

        Map<String, Group> queuesByDeveloperName = ITDeskRoutingService.queryQueuesByDeveloperName(
            queueDeveloperNames
        );
        Map<String, Contact> contactsByStudentId = ITDeskRoutingService.queryContactsByStudentId(studentIds);
        Map<String, List<Case>> openCasesByStudentId = ITDeskRoutingService.queryOpenCasesByStudentId(
            studentIds
        );
        Map<Id, Group> ownerQueuesById = collectOwnerQueues(openCasesByStudentId);

        List<Case> casesToInsert = new List<Case>();
        List<PendingInsert> inserts = new List<PendingInsert>();
        List<CaseComment> comments = new List<CaseComment>();
        List<Case> reusedFlags = new List<Case>();

        for (PendingInsert item : pending) {
            Boolean forceNew = item.request.forceNewTicket == true;
            if (!forceNew) {
                Case reusable = ITDeskRoutingService.findReusableOpenCase(
                    item.studentId,
                    item.request.category,
                    item.queueDeveloperName,
                    openCasesByStudentId,
                    ownerQueuesById
                );
                if (reusable != null) {
                    Group reusableQueue = ownerQueuesById.get(reusable.OwnerId);
                    if (reusableQueue == null) {
                        reusableQueue = queuesByDeveloperName.get(item.queueDeveloperName);
                    }
                    results[item.index] = buildExisting(reusable, reusableQueue);
                    comments.add(
                        ITDeskRoutingService.newPublishedComment(
                            reusable.Id,
                            buildAgentCommentBody(item.request, 'Student provided an update on an open ticket.')
                        )
                    );
                    reusedFlags.add(new Case(Id = reusable.Id, Reused_Existing_Ticket__c = true));
                    continue;
                }
            }

            item.queue = queuesByDeveloperName.get(item.queueDeveloperName);
            item.contact = contactsByStudentId.get(item.studentId);
            item.record = buildCase(item.request, item.queue, item.contact);
            casesToInsert.add(item.record);
            inserts.add(item);
        }

        if (!inserts.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(casesToInsert, false);
            Map<Id, Case> createdById = queryCreatedCases(saveResults);

            for (Integer i = 0; i < inserts.size(); i++) {
                PendingInsert item = inserts[i];
                Database.SaveResult saveResult = saveResults[i];
                if (saveResult.isSuccess()) {
                    Case created = createdById.get(saveResult.getId());
                    results[item.index] = buildSuccess(created, item.queue);
                    if (created != null) {
                        comments.add(
                            ITDeskRoutingService.newPublishedComment(
                                created.Id,
                                buildAgentCommentBody(item.request, 'Escalated by the Campus IT Triage Agent.')
                            )
                        );
                    }
                } else {
                    results[item.index] = buildDmlFailure();
                }
            }
        }

        if (!reusedFlags.isEmpty()) {
            Database.update(reusedFlags, false);
        }
        ITDeskRoutingService.insertPublishedComments(comments);
        logEscalations(requests, results);
        return results;
    }

    private class PendingInsert {
        Integer index;
        EscalationRequest request;
        String studentId;
        String queueDeveloperName;
        Group queue;
        Contact contact;
        Case record;
    }

    private static Boolean isValid(EscalationRequest request) {
        return request != null
            && String.isNotBlank(request.studentId)
            && String.isNotBlank(request.issueDescription);
    }

    private static EscalationResult buildValidationFailure() {
        EscalationResult result = new EscalationResult();
        result.isSuccess = false;
        result.isExistingTicket = false;
        result.message = 'I need a student ID and a brief description of the issue before I can create a ticket.';
        result.nextSteps = 'Ask the student for their campus Student ID and a short description of the problem, then retry this action.';
        return result;
    }

    private static EscalationResult buildDmlFailure() {
        EscalationResult result = new EscalationResult();
        result.isSuccess = false;
        result.isExistingTicket = false;
        result.message = 'I wasn\'t able to create a ticket just now.';
        result.nextSteps = 'Ask the student to retry in a moment or visit the campus IT walk-up desk.';
        return result;
    }

    private static EscalationResult buildExisting(Case existing, Group queue) {
        EscalationResult result = new EscalationResult();
        result.isSuccess = true;
        result.isExistingTicket = true;
        result.caseId = existing.Id;
        result.caseNumber = existing.CaseNumber;
        result.message = 'You already have ticket #' + existing.CaseNumber + ' open for this issue.';

        String ownerLabel = queue != null ? queue.Name : 'the assigned technician';
        result.nextSteps =
            'Share Case Number ' +
            existing.CaseNumber +
            ' with the student. It is still ' +
            existing.Status +
            ' with ' +
            ownerLabel +
            '. If this is a different problem, ask the student to confirm and retry with Force New Ticket set to true.';
        return result;
    }

    private static EscalationResult buildSuccess(Case created, Group queue) {
        EscalationResult result = new EscalationResult();
        result.isSuccess = true;
        result.isExistingTicket = false;
        if (created == null) {
            result.message = 'I created a ticket, but I could not load the case number yet.';
            result.nextSteps = 'Tell the student a technician will follow up, and retry a Case lookup if they need the number.';
            return result;
        }

        result.caseId = created.Id;
        result.caseNumber = created.CaseNumber;
        result.message = 'I\'ve created ticket #' + created.CaseNumber + ' for you.';

        String priorityLabel = String.isBlank(created.Priority)
            ? ITDeskRoutingService.PRIORITY_MEDIUM
            : created.Priority;
        if (queue != null) {
            result.nextSteps =
                'Share Case Number ' +
                created.CaseNumber +
                ' with the student. A technician on the ' +
                queue.Name +
                ' queue will follow up. Priority is ' +
                priorityLabel +
                '.';
        } else {
            result.nextSteps =
                'Share Case Number ' +
                created.CaseNumber +
                ' with the student. The ticket was created but could not be routed to a specialist queue, so a technician will pick it up from the default owner. Priority is ' +
                priorityLabel +
                '.';
        }
        return result;
    }

    private static Case buildCase(EscalationRequest request, Group queue, Contact student) {
        Case ticket = new Case();
        ticket.Subject = buildSubject(request);
        ticket.Description = buildDescription(request);
        ticket.Origin = CASE_ORIGIN_WEB;
        ticket.Status = CASE_STATUS_NEW;
        ticket.Priority = ITDeskRoutingService.resolvePriority(request.urgency);
        ticket.Student_ID__c = ITDeskRoutingService.normalizeStudentId(request.studentId);
        ticket.IT_Category__c = ITDeskRoutingService.resolveCategoryLabel(request.category);
        ticket.Agent_Sourced__c = true;
        ticket.Reused_Existing_Ticket__c = false;
        ticket.Self_Service_Attempted__c = request.selfServiceAttempted == true;
        if (String.isNotBlank(request.selfServiceArticle)) {
            String article = request.selfServiceArticle.trim();
            ticket.Self_Service_Article__c = article.length() > 80 ? article.substring(0, 80) : article;
        }
        ticket.First_Response_Due__c = ITDeskAuditService.firstResponseDue(ticket.Priority);
        if (String.isNotBlank(request.studentEmail)) {
            ticket.SuppliedEmail = request.studentEmail.trim();
        }
        if (student != null) {
            ticket.ContactId = student.Id;
        }
        if (queue != null) {
            ticket.OwnerId = queue.Id;
        }
        return ticket;
    }

    private static String buildSubject(EscalationRequest request) {
        String categoryLabel = String.isBlank(request.category) ? 'General' : request.category.trim();
        String description = request.issueDescription.trim();
        if (description.length() > SUBJECT_DESC_LIMIT) {
            description = description.substring(0, SUBJECT_DESC_LIMIT) + '...';
        }

        String subject = 'Campus IT: ' + categoryLabel + ' — ' + description;
        if (subject.length() > SUBJECT_MAX_LENGTH) {
            subject = subject.substring(0, SUBJECT_MAX_LENGTH);
        }
        return subject;
    }

    private static String buildDescription(EscalationRequest request) {
        List<String> lines = new List<String>{
            request.issueDescription.trim(),
            '',
            'Student ID: ' + request.studentId.trim()
        };
        if (String.isNotBlank(request.category)) {
            lines.add('Category: ' + request.category.trim());
        }
        if (String.isNotBlank(request.urgency)) {
            lines.add('Reported urgency: ' + request.urgency.trim());
        }
        if (String.isNotBlank(request.studentEmail)) {
            lines.add('Student email: ' + request.studentEmail.trim());
        }
        lines.add('Source: Agentforce Campus IT Triage Agent');
        return String.join(lines, '\n');
    }

    private static String buildAgentCommentBody(EscalationRequest request, String header) {
        List<String> lines = new List<String>{ header, '', request.issueDescription.trim() };
        if (String.isNotBlank(request.category)) {
            lines.add('Category: ' + request.category.trim());
        }
        if (String.isNotBlank(request.urgency)) {
            lines.add('Reported urgency: ' + request.urgency.trim());
        }
        return String.join(lines, '\n');
    }

    private static Map<Id, Group> collectOwnerQueues(Map<String, List<Case>> openCasesByStudentId) {
        Set<Id> ownerIds = new Set<Id>();
        for (List<Case> tickets : openCasesByStudentId.values()) {
            for (Case ticket : tickets) {
                ownerIds.add(ticket.OwnerId);
            }
        }
        return ITDeskRoutingService.queryQueuesById(ownerIds);
    }

    private static Map<Id, Case> queryCreatedCases(Database.SaveResult[] saveResults) {
        Set<Id> successIds = new Set<Id>();
        for (Database.SaveResult saveResult : saveResults) {
            if (saveResult.isSuccess()) {
                successIds.add(saveResult.getId());
            }
        }
        if (successIds.isEmpty()) {
            return new Map<Id, Case>();
        }
        return new Map<Id, Case>([
            SELECT Id, CaseNumber, Priority, OwnerId
            FROM Case
            WHERE Id IN :successIds
        ]);
    }

    private static void logEscalations(List<EscalationRequest> requests, List<EscalationResult> results) {
        List<Campus_IT_Interaction__c> rows = new List<Campus_IT_Interaction__c>();
        for (Integer i = 0; i < results.size(); i++) {
            EscalationResult result = results[i];
            if (result == null) {
                continue;
            }
            EscalationRequest request = i < requests.size() ? requests[i] : null;
            String outcome = ITDeskAuditService.OUTCOME_FAILED;
            if (result.isSuccess == true) {
                outcome = result.isExistingTicket == true
                    ? ITDeskAuditService.OUTCOME_REUSED
                    : ITDeskAuditService.OUTCOME_CREATED;
            }
            rows.add(
                ITDeskAuditService.newInteraction(
                    ITDeskAuditService.ACTION_ESCALATE,
                    outcome,
                    result.isSuccess,
                    request == null ? null : request.studentId,
                    result.caseId,
                    result.caseNumber,
                    request == null ? null : ITDeskRoutingService.resolveCategoryLabel(request.category),
                    request == null ? null : request.selfServiceArticle,
                    result.message
                )
            );
        }
        ITDeskAuditService.log(rows);
    }
}
