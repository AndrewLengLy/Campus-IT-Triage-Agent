/**
 * Contract tests for the routing configuration this repo actually ships.
 *
 * Every other test injects in-memory rules. These read the deployed
 * IT_Category_Queue_Map__mdt rows and the packaged Campus_IT_* queues, so a change to the
 * Custom Metadata or a removed queue fails here rather than silently misrouting tickets in
 * production. Custom Metadata and Group are metadata/setup objects, so tests read them
 * without SeeAllData.
 */
@IsTest
private class ITDeskQueueRoutingTest {
    /** Category input, the queue DeveloperName it must reach, and the Case label it must store. */
    private class RoutingExpectation {
        String category;
        String queueDeveloperName;
        String caseCategoryLabel;

        RoutingExpectation(String category, String queueDeveloperName, String caseCategoryLabel) {
            this.category = category;
            this.queueDeveloperName = queueDeveloperName;
            this.caseCategoryLabel = caseCategoryLabel;
        }
    }

    private static List<RoutingExpectation> expectations() {
        return new List<RoutingExpectation>{
            new RoutingExpectation('Network', 'Campus_IT_Network', 'Network'),
            new RoutingExpectation('WiFi', 'Campus_IT_Network', 'Network'),
            new RoutingExpectation('VPN', 'Campus_IT_Network', 'Network'),
            new RoutingExpectation('Hardware', 'Campus_IT_Hardware', 'Hardware'),
            new RoutingExpectation('Laptop', 'Campus_IT_Hardware', 'Hardware'),
            new RoutingExpectation('Printer', 'Campus_IT_Hardware', 'Hardware'),
            new RoutingExpectation('Software', 'Campus_IT_Software', 'Software'),
            new RoutingExpectation('Outlook', 'Campus_IT_Software', 'Software'),
            new RoutingExpectation('License', 'Campus_IT_Software', 'Software'),
            new RoutingExpectation('Account', 'Campus_IT_Identity', 'Account'),
            new RoutingExpectation('Password', 'Campus_IT_Identity', 'Account'),
            new RoutingExpectation('MFA', 'Campus_IT_Identity', 'Account'),
            new RoutingExpectation('Eduroam', 'Campus_IT_Network', 'Network'),
            new RoutingExpectation('Printing', 'Campus_IT_Hardware', 'Hardware'),
            new RoutingExpectation('LMS', 'Campus_IT_Software', 'Software'),
            new RoutingExpectation('Provisioning', 'Campus_IT_Identity', 'Account'),
            new RoutingExpectation('Parking permits', 'Campus_IT_General', 'General')
        };
    }

    @IsTest
    static void deployedRules_referenceQueuesThatExistAndAcceptCases() {
        List<IT_Category_Queue_Map__mdt> rules = IT_Category_Queue_Map__mdt.getAll().values();
        Assert.isFalse(rules.isEmpty(), 'The repo must ship at least one IT_Category_Queue_Map row.');

        Set<String> referenced = new Set<String>();
        Integer defaults = 0;
        for (IT_Category_Queue_Map__mdt rule : rules) {
            Assert.isTrue(
                String.isNotBlank(rule.Queue_Developer_Name__c),
                'Routing rule ' + rule.DeveloperName + ' has no queue and can never route a ticket.'
            );
            referenced.add(rule.Queue_Developer_Name__c);
            if (rule.Is_Default__c) {
                defaults++;
            }
        }

        Assert.areEqual(
            1,
            defaults,
            'Exactly one routing rule may be the default. More than one makes the fallback queue ' +
            'depend on Custom Metadata iteration order, which Apex does not define.'
        );

        Map<String, Group> queues = ITDeskRoutingService.queryQueuesByDeveloperName(referenced);
        for (String developerName : referenced) {
            Assert.isTrue(
                queues.containsKey(developerName),
                'Routing rules point at queue ' + developerName + ', which is not deployed to this org.'
            );
        }

        Set<Id> caseEnabled = new Set<Id>();
        for (QueueSobject supported : [
            SELECT QueueId
            FROM QueueSobject
            WHERE SobjectType = 'Case' AND QueueId IN :queues.values()
        ]) {
            caseEnabled.add(supported.QueueId);
        }
        for (String developerName : referenced) {
            Assert.isTrue(
                caseEnabled.contains(queues.get(developerName).Id),
                'Queue ' + developerName + ' is not enabled for the Case object, so owner assignment ' +
                'to it will fail at DML time.'
            );
        }
    }

    @IsTest
    static void deployedRules_coverEveryCampusItQueue() {
        Set<String> referenced = new Set<String>();
        for (IT_Category_Queue_Map__mdt rule : IT_Category_Queue_Map__mdt.getAll().values()) {
            referenced.add(rule.Queue_Developer_Name__c);
        }

        for (String developerName : ITDeskTestFactory.DEPLOYED_QUEUES) {
            Assert.isTrue(
                referenced.contains(developerName),
                'No routing rule sends work to ' + developerName + ', so the queue can never fill.'
            );
        }
    }

    @IsTest
    static void resolveQueue_usesTheDeployedRulesForEveryCategory() {
        ITDeskTestFactory.useDeployedRouting();

        for (RoutingExpectation expected : expectations()) {
            Assert.areEqual(
                expected.queueDeveloperName,
                ITDeskRoutingService.resolveQueueDeveloperName(expected.category),
                'Deployed routing must send "' + expected.category + '" to ' + expected.queueDeveloperName + '.'
            );
            Assert.areEqual(
                expected.caseCategoryLabel,
                ITDeskRoutingService.resolveCategoryLabel(expected.category),
                'Deployed routing must label "' + expected.category + '" as ' + expected.caseCategoryLabel + '.'
            );
        }
    }

    @IsTest
    static void escalate_assignsEveryCampusItQueueEndToEnd() {
        ITDeskTestFactory.useDeployedRouting();

        List<RoutingExpectation> expected = expectations();
        List<ITDeskTicketEscalation.EscalationRequest> requests =
            new List<ITDeskTicketEscalation.EscalationRequest>();
        for (Integer i = 0; i < expected.size(); i++) {
            requests.add(
                ITDeskTestFactory.escalation(
                    ITDeskTestFactory.bulkStudentId(i),
                    'Escalation routed by the deployed rules: ' + expected[i].category,
                    'Medium',
                    expected[i].category
                )
            );
        }

        Test.startTest();
        List<ITDeskTicketEscalation.EscalationResult> results = ITDeskTicketEscalation.escalate(requests);
        Test.stopTest();

        Map<String, Group> queues = ITDeskRoutingService.queryQueuesByDeveloperName(
            new Set<String>(ITDeskTestFactory.DEPLOYED_QUEUES)
        );
        Map<Id, Case> created = new Map<Id, Case>(
            [SELECT Id, OwnerId, IT_Category__c FROM Case]
        );

        Set<Id> queuesUsed = new Set<Id>();
        for (Integer i = 0; i < expected.size(); i++) {
            Assert.isTrue(
                results[i].isSuccess,
                'Escalating "' + expected[i].category + '" should have created a Case.'
            );
            Case ticket = created.get(results[i].caseId);
            Assert.areEqual(
                queues.get(expected[i].queueDeveloperName).Id,
                ticket.OwnerId,
                '"' + expected[i].category + '" must land on ' + expected[i].queueDeveloperName + '.'
            );
            Assert.areEqual(
                expected[i].caseCategoryLabel,
                ticket.IT_Category__c,
                '"' + expected[i].category + '" must be stored as ' + expected[i].caseCategoryLabel + '.'
            );
            queuesUsed.add(ticket.OwnerId);
        }

        Assert.areEqual(
            ITDeskTestFactory.DEPLOYED_QUEUES.size(),
            queuesUsed.size(),
            'This test must exercise all five Campus IT queues, not a subset.'
        );
    }

    @IsTest
    static void firstResponseDue_usesTheDeployedSlaRules() {
        Map<String, Decimal> hoursByPriority = new Map<String, Decimal>();
        for (IT_SLA_Rule__mdt rule : IT_SLA_Rule__mdt.getAll().values()) {
            hoursByPriority.put(rule.Priority__c, rule.First_Response_Hours__c);
        }

        for (String priority : new List<String>{ 'High', 'Medium', 'Low' }) {
            Assert.isTrue(
                hoursByPriority.containsKey(priority),
                'The repo must ship an SLA rule for ' + priority + ' priority.'
            );

            Integer hours = hoursByPriority.get(priority).intValue();
            Datetime lowerBound = Datetime.now().addHours(hours - 1);
            Datetime due = ITDeskAuditService.firstResponseDue(priority);
            Datetime upperBound = Datetime.now().addHours(hours + 1);

            Assert.isTrue(
                due > lowerBound && due < upperBound,
                priority + ' priority must set a first response due about ' + hours + ' hours out, got ' + due
            );
        }

        Assert.isTrue(
            hoursByPriority.get('High') < hoursByPriority.get('Medium'),
            'High priority must have a tighter first-response target than Medium.'
        );
        Assert.isTrue(
            hoursByPriority.get('Medium') < hoursByPriority.get('Low'),
            'Medium priority must have a tighter first-response target than Low.'
        );
    }
}
