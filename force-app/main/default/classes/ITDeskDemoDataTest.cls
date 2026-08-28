/**
 * Coverage for the sample-data seeder.
 *
 * The seeder is what a reviewer runs first, so these tests assert the shape of the org it
 * produces: students, tickets spread across the Campus IT queues, a follow-up comment, and an
 * audit trail with both a match and a miss. It runs against the deployed routing rules, so a
 * broken Custom Metadata change shows up here too.
 */
@IsTest
private class ITDeskDemoDataTest {
    @IsTest
    static void seed_producesAWorkingOrgOnAFreshDeploy() {
        Test.startTest();
        ITDeskDemoData.SeedResult result = ITDeskDemoData.seed();
        Test.stopTest();

        Assert.isFalse(result.alreadySeeded, 'An empty org must actually be seeded.');
        Assert.areEqual(8, result.students, 'Every sample student must be created.');
        Assert.areEqual(7, result.casesOpened, 'Every sample escalation must open a ticket.');
        Assert.areEqual(
            2,
            result.selfServiceDeflections,
            'Two students must be fully deflected, otherwise the deflection rate reads as zero.'
        );
        Assert.isTrue(result.auditRows > 0, 'The audit trail must not be empty after seeding.');

        Assert.areEqual(
            8,
            [SELECT COUNT() FROM Contact WHERE Student_ID__c IN :ITDeskDemoData.SAMPLE_STUDENT_IDS],
            'Sample students must exist as Contacts so Cases can link to them.'
        );
        Assert.areEqual(
            7,
            [SELECT COUNT() FROM Case WHERE Agent_Sourced__c = TRUE],
            'The sample org must show seven triage-sourced Cases.'
        );
    }

    @IsTest
    static void seed_spreadsSampleTicketsAcrossEveryCampusItQueue() {
        Test.startTest();
        ITDeskDemoData.seed();
        Test.stopTest();

        Map<Id, Group> campusQueues = new Map<Id, Group>(
            [
                SELECT Id, DeveloperName
                FROM Group
                WHERE Type = 'Queue' AND DeveloperName IN :ITDeskTestFactory.DEPLOYED_QUEUES
            ]
        );

        Set<String> queuesUsed = new Set<String>();
        for (Case ticket : [SELECT OwnerId, IT_Category__c, First_Response_Due__c FROM Case]) {
            Assert.isTrue(
                campusQueues.containsKey(ticket.OwnerId),
                'Every sample ticket must land on a Campus IT queue, not on the running user.'
            );
            Assert.isNotNull(
                ticket.First_Response_Due__c,
                'Every sample ticket must carry an SLA due date so the list views are meaningful.'
            );
            queuesUsed.add(campusQueues.get(ticket.OwnerId).DeveloperName);
        }

        Assert.areEqual(
            5,
            queuesUsed.size(),
            'The sample data must fill all five Campus IT queues, so a reviewer sees routing work. Filled: ' +
            queuesUsed
        );
    }

    @IsTest
    static void seed_leavesBothAMatchedAndAMissedLookupInTheAuditTrail() {
        Test.startTest();
        ITDeskDemoData.seed();
        Test.stopTest();

        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_MATCHED
            ],
            'Two self-service matches give the operations snapshot a real deflection rate.'
        );
        Assert.areEqual(
            7,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_CREATED
            ],
            'Seven escalations must be audited as Created.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_UPDATED
            ],
            'The follow-up comment must be audited as Updated.'
        );
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Outcome__c = :ITDeskAuditService.OUTCOME_NOT_FOUND
            ],
            'A miss must be seeded too, so the trail is not uniformly successful.'
        );
    }

    @IsTest
    static void seed_isSafeToRunTwice() {
        ITDeskDemoData.seed();

        Test.startTest();
        ITDeskDemoData.SeedResult second = ITDeskDemoData.seed();
        Test.stopTest();

        Assert.isTrue(second.alreadySeeded, 'A second run must detect the existing sample data.');
        Assert.areEqual(
            7,
            [SELECT COUNT() FROM Case WHERE Agent_Sourced__c = TRUE],
            'Re-running the seeder must not duplicate tickets.'
        );
        Assert.areEqual(
            8,
            [SELECT COUNT() FROM Contact WHERE Student_ID__c IN :ITDeskDemoData.SAMPLE_STUDENT_IDS],
            'Contacts upsert on Student ID, so a second run must not duplicate students.'
        );
    }

    @IsTest
    static void seed_linksEverySampleTicketToItsStudentContact() {
        Test.startTest();
        ITDeskDemoData.seed();
        Test.stopTest();

        Map<String, Id> contactByStudentId = new Map<String, Id>();
        for (Contact student : [
            SELECT Id, Student_ID__c
            FROM Contact
            WHERE Student_ID__c IN :ITDeskDemoData.SAMPLE_STUDENT_IDS
        ]) {
            contactByStudentId.put(student.Student_ID__c, student.Id);
        }

        for (Case ticket : [SELECT Student_ID__c, ContactId, SuppliedEmail FROM Case]) {
            Assert.areEqual(
                contactByStudentId.get(ticket.Student_ID__c),
                ticket.ContactId,
                'Ticket for ' + ticket.Student_ID__c + ' must be linked to that student Contact.'
            );
            Assert.isTrue(
                String.isNotBlank(ticket.SuppliedEmail),
                'Sample tickets must carry a reply address so the Case layout has something to show.'
            );
        }
    }
}
