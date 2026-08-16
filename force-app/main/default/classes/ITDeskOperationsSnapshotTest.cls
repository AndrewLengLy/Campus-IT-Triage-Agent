@IsTest
private class ITDeskOperationsSnapshotTest {
    @IsTest
    static void getSnapshot_reportsOpenLoadAndDeflection() {
        Case waiting = new Case(
            Subject = 'Campus IT: Hardware — laptop will not power on',
            Origin = 'Web',
            Status = 'New',
            Priority = 'High',
            Student_ID__c = 'S10000002',
            IT_Category__c = 'Hardware',
            Agent_Sourced__c = true
        );
        Case medium = new Case(
            Subject = 'Campus IT: Network — wifi dropout',
            Origin = 'Web',
            Status = 'New',
            Priority = 'Medium',
            Student_ID__c = 'S10000001',
            IT_Category__c = 'Network',
            Agent_Sourced__c = true
        );
        insert new List<Case>{ waiting, medium };
        waiting = [SELECT Id, CaseNumber FROM Case WHERE Id = :waiting.Id];
        Test.setCreatedDate(waiting.Id, Datetime.now().addHours(-6));

        insert new List<Campus_IT_Interaction__c>{
            ITDeskAuditService.newInteraction(
                ITDeskAuditService.ACTION_SELF_SERVICE,
                ITDeskAuditService.OUTCOME_MATCHED,
                true,
                'S10000001',
                null,
                null,
                'Network',
                'Reconnect to campus WiFi',
                'Matched'
            ),
            ITDeskAuditService.newInteraction(
                ITDeskAuditService.ACTION_SELF_SERVICE,
                ITDeskAuditService.OUTCOME_MATCHED,
                true,
                'S10000003',
                null,
                null,
                'Account',
                'Reset campus password',
                'Matched'
            ),
            ITDeskAuditService.newInteraction(
                ITDeskAuditService.ACTION_ESCALATE,
                ITDeskAuditService.OUTCOME_CREATED,
                true,
                'S10000002',
                waiting.Id,
                '00001001',
                'Hardware',
                'Laptop will not power on',
                'Created'
            )
        };

        ITDeskOperationsSnapshot.SnapshotRequest filtered = new ITDeskOperationsSnapshot.SnapshotRequest();
        filtered.queueName = 'zzzz-no-such-queue';

        Test.startTest();
        List<ITDeskOperationsSnapshot.SnapshotResult> wholeDesk = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>()
        );
        List<ITDeskOperationsSnapshot.SnapshotResult> noMatch = ITDeskOperationsSnapshot.getSnapshot(
            new List<ITDeskOperationsSnapshot.SnapshotRequest>{ filtered }
        );
        Test.stopTest();

        Assert.areEqual(1, wholeDesk.size());
        ITDeskOperationsSnapshot.SnapshotResult result = wholeDesk[0];
        Assert.areEqual(2, result.openTicketCount);
        Assert.areEqual(1, result.highPriorityOpen);
        Assert.areEqual(waiting.CaseNumber, result.oldestCaseNumber);
        Assert.isTrue(result.oldestWaitHours >= 5);
        Assert.areEqual(2, result.selfServiceMatchesToday);
        Assert.areEqual(1, result.escalationsToday);
        Assert.areEqual(Decimal.valueOf('66.7'), result.deflectionRate);
        Assert.isTrue(result.message.contains('open agent-sourced tickets'));
        Assert.isTrue(String.isNotBlank(result.queueBreakdown));

        Assert.areEqual(0, noMatch[0].openTicketCount);
        Assert.areEqual(0, noMatch[0].highPriorityOpen);
        Assert.isNull(noMatch[0].oldestCaseNumber);
        Assert.isTrue(noMatch[0].message.contains('No agent-sourced tickets are waiting'));

        Assert.areEqual(
            2,
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Action_Type__c = :ITDeskAuditService.ACTION_OPERATIONS
                AND Outcome__c = :ITDeskAuditService.OUTCOME_SNAPSHOT
            ]
        );
    }
}
