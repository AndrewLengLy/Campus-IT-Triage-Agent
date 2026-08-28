/**
 * Behaviour coverage for ITDeskOperationsSnapshot: open load, oldest wait, the queue
 * breakdown, and today's deflection rate.
 *
 * Quiet-desk and non-triage-sourced edges live in ITDeskNegativePathTest; 200-record batches
 * live in ITDeskBulkTest.
 */
@IsTest
private class ITDeskOperationsSnapshotTest {
    @IsTest
    static void getSnapshot_reportsOpenLoadOldestWaitAndDeflection() {
        Case waiting = agentSourcedCase('Hardware', 'High', 'S10000002');
        Case medium = agentSourcedCase('Network', 'Medium', 'S10000001');
        insert new List<Case>{ waiting, medium };
        waiting = [SELECT Id, CaseNumber FROM Case WHERE Id = :waiting.Id];
        Test.setCreatedDate(waiting.Id, Datetime.now().addHours(-6));

        insert new List<Campus_IT_Interaction__c>{
            selfServiceMatch('S10000001', 'Network'),
            selfServiceMatch('S10000003', 'Account'),
            ITDeskAuditService.newInteraction(
                ITDeskAuditService.ACTION_ESCALATE,
                ITDeskAuditService.OUTCOME_CREATED,
                true,
                'S10000002',
                waiting.Id,
                waiting.CaseNumber,
                'Hardware',
                'Laptop will not power on',
                'Created'
            )
        };

        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>()
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'An empty request list must still produce one whole-desk snapshot.');
        ITDeskOperationsSnapshot.SnapshotResult result = results[0];
        Assert.areEqual(2, result.openTicketCount);
        Assert.areEqual(1, result.highPriorityOpen, 'Only the High priority ticket may be counted as high.');
        Assert.areEqual(
            waiting.CaseNumber,
            result.oldestCaseNumber,
            'The oldest open ticket is the one a supervisor needs named.'
        );
        Assert.isTrue(result.oldestWaitHours >= 5, 'A ticket created six hours ago has waited about six hours.');
        Assert.areEqual(2, result.selfServiceMatchesToday);
        Assert.areEqual(1, result.escalationsToday);
        Assert.areEqual(
            Decimal.valueOf('66.7'),
            result.deflectionRate,
            'Two matches against two matches plus one new ticket is 66.7 percent deflection.'
        );
        Assert.isTrue(result.message.contains('open agent-sourced tickets'));
        Assert.isTrue(String.isNotBlank(result.queueBreakdown));
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_OPERATIONS
            ],
            'One snapshot request must produce exactly one Operations audit row.'
        );
    }

    @IsTest
    static void getSnapshot_filtersByQueueNameAndNamesTheQueueInTheBreakdown() {
        Group networkQueue = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Campus_IT_Network'
            LIMIT 1
        ];
        Group hardwareQueue = [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Campus_IT_Hardware'
            LIMIT 1
        ];

        Case onNetwork = agentSourcedCase('Network', 'Medium', 'S10000001');
        onNetwork.OwnerId = networkQueue.Id;
        Case onHardware = agentSourcedCase('Hardware', 'High', 'S10000002');
        onHardware.OwnerId = hardwareQueue.Id;
        insert new List<Case>{ onNetwork, onHardware };

        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>{
                ITDeskTestFactory.snapshot(null),
                ITDeskTestFactory.snapshot(networkQueue.Name),
                ITDeskTestFactory.snapshot('zzzz-no-such-queue')
            }
        );
        Test.stopTest();

        Assert.areEqual(2, results[0].openTicketCount, 'The unfiltered snapshot must see the whole desk.');
        Assert.isTrue(
            results[0].queueBreakdown.contains(networkQueue.Name) &&
            results[0].queueBreakdown.contains(hardwareQueue.Name),
            'The breakdown must name both queues so a supervisor can see where the load sits. Got: ' +
            results[0].queueBreakdown
        );

        Assert.areEqual(
            1,
            results[1].openTicketCount,
            'Filtering by a queue name must scope the count to that queue.'
        );
        Assert.areEqual(0, results[1].highPriorityOpen, 'The high priority ticket sits on the other queue.');
        Assert.isTrue(
            results[1].message.contains(networkQueue.Name.toLowerCase()),
            'A filtered snapshot must say which queue it describes.'
        );

        Assert.areEqual(0, results[2].openTicketCount, 'A filter matching no queue must report an empty desk.');
        Assert.areEqual('None', results[2].queueBreakdown);
    }

    @IsTest
    static void getSnapshot_labelsTicketsOutsideTheCampusItQueuesSeparately() {
        Case ownedByAUser = agentSourcedCase('General', 'Medium', 'S10000001');
        ownedByAUser.OwnerId = UserInfo.getUserId();
        insert ownedByAUser;

        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> results = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>{ ITDeskTestFactory.snapshot(null) }
        );
        Test.stopTest();

        Assert.areEqual(1, results[0].openTicketCount);
        Assert.isTrue(
            results[0].queueBreakdown.contains('Unassigned / other'),
            'A ticket that never reached a Campus IT queue must be visible as unrouted work. Got: ' +
            results[0].queueBreakdown
        );
    }

    private static Case agentSourcedCase(String category, String priority, String studentId) {
        return new Case(
            Subject = 'Campus IT: ' + category + ' — seeded for the operations snapshot',
            Origin = 'Web',
            Status = 'New',
            Priority = priority,
            Student_ID__c = studentId,
            IT_Category__c = category,
            Agent_Sourced__c = true
        );
    }

    private static Campus_IT_Interaction__c selfServiceMatch(String studentId, String category) {
        return ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_SELF_SERVICE,
            ITDeskAuditService.OUTCOME_MATCHED,
            true,
            studentId,
            null,
            null,
            category,
            'Seeded article',
            'Matched'
        );
    }
}
