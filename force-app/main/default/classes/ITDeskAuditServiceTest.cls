@IsTest
private class ITDeskAuditServiceTest {
    @IsTest
    static void firstResponseDue_usesOverrideHours() {
        ITDeskAuditService.slaOverrides = new List<IT_SLA_Rule__mdt>{
            new IT_SLA_Rule__mdt(Priority__c = 'High', First_Response_Hours__c = 4),
            new IT_SLA_Rule__mdt(Priority__c = 'Low', First_Response_Hours__c = 40)
        };

        Datetime beforeHigh = Datetime.now().addHours(3);
        Datetime highDue = ITDeskAuditService.firstResponseDue('High');
        Datetime afterHigh = Datetime.now().addHours(5);
        Datetime mediumDue = ITDeskAuditService.firstResponseDue(null);
        Datetime lowDue = ITDeskAuditService.firstResponseDue('low');

        Assert.isTrue(highDue > beforeHigh);
        Assert.isTrue(highDue < afterHigh);
        Assert.isTrue(mediumDue > Datetime.now().addHours(15));
        Assert.isTrue(lowDue > Datetime.now().addHours(39));
    }

    @IsTest
    static void log_insertsValidRowsAndIgnoresEmpty() {
        Campus_IT_Interaction__c row = ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_SELF_SERVICE,
            ITDeskAuditService.OUTCOME_MATCHED,
            true,
            's 1000-0001',
            null,
            null,
            'Network',
            'Reconnect to campus WiFi ' + 'x'.repeat(80),
            'Matched a known-issue guide.'
        );
        Assert.areEqual(80, row.Article_Title__c.length(), 'Article titles must fit the text field.');

        Test.startTest();
        ITDeskAuditService.log(null);
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>());
        ITDeskAuditService.log(new List<Campus_IT_Interaction__c>{ null, row });
        Test.stopTest();

        Campus_IT_Interaction__c stored = [
            SELECT Action_Type__c, Outcome__c, Success__c, Student_ID__c, Category__c, Article_Title__c
            FROM Campus_IT_Interaction__c
            LIMIT 1
        ];
        Assert.areEqual(ITDeskAuditService.ACTION_SELF_SERVICE, stored.Action_Type__c);
        Assert.areEqual(ITDeskAuditService.OUTCOME_MATCHED, stored.Outcome__c);
        Assert.isTrue(stored.Success__c);
        Assert.areEqual('S10000001', stored.Student_ID__c);
        Assert.areEqual('Network', stored.Category__c);
        Assert.areEqual('Reconnect to campus WiFi', stored.Article_Title__c);
    }

    @IsTest
    static void guard_blocksUpdateAndDelete() {
        insert ITDeskAuditService.newInteraction(
            ITDeskAuditService.ACTION_STATUS,
            ITDeskAuditService.OUTCOME_FOUND,
            true,
            'S10000001',
            null,
            '00001234',
            'Network',
            null,
            'Ticket found.'
        );
        Campus_IT_Interaction__c stored = [SELECT Id, Outcome__c FROM Campus_IT_Interaction__c LIMIT 1];

        Test.startTest();
        Boolean updateBlocked = false;
        try {
            stored.Outcome__c = ITDeskAuditService.OUTCOME_FAILED;
            update stored;
        } catch (DmlException e) {
            updateBlocked = e.getMessage().contains('append-only');
        }
        Boolean deleteBlocked = false;
        try {
            delete stored;
        } catch (DmlException e) {
            deleteBlocked = e.getMessage().contains('append-only');
        }
        Test.stopTest();

        Assert.isTrue(updateBlocked, 'Updates must be rejected.');
        Assert.isTrue(deleteBlocked, 'Deletes must be rejected.');
        Assert.areEqual(1, [SELECT COUNT() FROM Campus_IT_Interaction__c]);
    }
}
