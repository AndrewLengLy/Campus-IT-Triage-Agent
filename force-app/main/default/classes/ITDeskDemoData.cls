/**
 * Idempotent demo Contacts plus a one-time walkthrough seed so list views
 * and the operations snapshot are not empty after first deploy.
 * Run from the CLI: sf apex run --file scripts/apex/createDemoData.apex --target-org campus-it-dev
 */
public with sharing class ITDeskDemoData {
    public static final String DEMO_ALEX = 'S10000001';
    public static final String DEMO_JORDAN = 'S10000002';
    public static final String DEMO_SAM = 'S10000003';

    public static List<Contact> create() {
        List<Contact> students = new List<Contact>{
            new Contact(
                FirstName = 'Alex',
                LastName = 'Rivera',
                Email = 'alex.rivera@campus.edu',
                Student_ID__c = DEMO_ALEX
            ),
            new Contact(
                FirstName = 'Jordan',
                LastName = 'Chen',
                Email = 'jordan.chen@campus.edu',
                Student_ID__c = DEMO_JORDAN
            ),
            new Contact(
                FirstName = 'Sam',
                LastName = 'Patel',
                Email = 'sam.patel@campus.edu',
                Student_ID__c = DEMO_SAM
            )
        };
        upsert students Contact.Student_ID__c;
        seedWalkthroughIfNeeded();
        return students;
    }

    private static void seedWalkthroughIfNeeded() {
        try {
            Boolean hasDemoCase = [
                SELECT COUNT()
                FROM Case
                WHERE Student_ID__c = :DEMO_JORDAN AND Agent_Sourced__c = TRUE
            ] > 0;
            Boolean hasDemoLog = [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Student_ID__c IN :new Set<String>{ DEMO_ALEX, DEMO_JORDAN, DEMO_SAM }
            ] > 0;
            if (hasDemoCase && hasDemoLog) {
                return;
            }

            if (!hasDemoLog) {
                ITDeskSelfService.SelfServiceRequest wifi = new ITDeskSelfService.SelfServiceRequest();
                wifi.issueDescription = 'Campus WiFi keeps dropping in the residence hall.';
                wifi.category = 'Network';
                wifi.studentId = DEMO_ALEX;
                ITDeskSelfService.findGuide(new List<ITDeskSelfService.SelfServiceRequest>{ wifi });
            }

            if (!hasDemoCase) {
                ITDeskTicketEscalation.EscalationRequest escalate = new ITDeskTicketEscalation.EscalationRequest();
                escalate.studentId = DEMO_JORDAN;
                escalate.issueDescription = 'Laptop will not power on before an exam.';
                escalate.urgency = 'High';
                escalate.category = 'Hardware';
                escalate.studentEmail = 'jordan.chen@campus.edu';
                escalate.selfServiceAttempted = true;
                escalate.selfServiceArticle = 'Laptop will not power on';
                List<ITDeskTicketEscalation.EscalationResult> created = ITDeskTicketEscalation.escalate(
                    new List<ITDeskTicketEscalation.EscalationRequest>{ escalate }
                );
                if (!created.isEmpty() && created[0].isSuccess == true) {
                    ITDeskTicketStatus.StatusRequest status = new ITDeskTicketStatus.StatusRequest();
                    status.caseNumber = created[0].caseNumber;
                    status.studentId = DEMO_JORDAN;
                    ITDeskTicketStatus.checkStatus(new List<ITDeskTicketStatus.StatusRequest>{ status });
                }
            }

            ITDeskTicketStatus.StatusRequest missing = new ITDeskTicketStatus.StatusRequest();
            missing.studentId = DEMO_SAM;
            ITDeskTicketStatus.checkStatus(new List<ITDeskTicketStatus.StatusRequest>{ missing });
        } catch (Exception ignored) {
            // Demo seed must never fail Contact upsert.
        }
    }
}
