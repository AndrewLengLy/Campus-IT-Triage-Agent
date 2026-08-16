@IsTest
private class ITDeskSelfServiceTest {
    @IsTest
    static void findGuide_matchesWifiAndRequiresEscalationForLaptop() {
        ITDeskSelfService.knownIssueOverrides = new List<IT_Known_Issue__mdt>{
            new IT_Known_Issue__mdt(
                Title__c = 'Reconnect to campus WiFi',
                Keywords__c = 'wifi,wireless,eduroam',
                Category__c = 'Network',
                Resolution_Steps__c = 'Forget the network and rejoin.',
                Requires_Escalation__c = false,
                Is_Active__c = true
            ),
            new IT_Known_Issue__mdt(
                Title__c = 'Laptop will not power on',
                Keywords__c = 'laptop,no power',
                Category__c = 'Hardware',
                Resolution_Steps__c = 'Try a different charger, then escalate.',
                Requires_Escalation__c = true,
                Is_Active__c = true
            ),
            new IT_Known_Issue__mdt(
                Title__c = 'Inactive article',
                Keywords__c = 'wifi',
                Is_Active__c = false
            )
        };

        ITDeskSelfService.SelfServiceRequest wifi = new ITDeskSelfService.SelfServiceRequest();
        wifi.issueDescription = 'I cannot stay on campus Wi-Fi in the library.';
        wifi.category = 'Network';

        ITDeskSelfService.SelfServiceRequest laptop = new ITDeskSelfService.SelfServiceRequest();
        laptop.issueDescription = 'My laptop has no power and will not start.';

        ITDeskSelfService.SelfServiceRequest unknown = new ITDeskSelfService.SelfServiceRequest();
        unknown.issueDescription = 'The dining hall app crashed.';

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> results = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{ wifi, laptop, unknown, null }
        );
        Test.stopTest();

        Assert.areEqual(4, results.size());
        Assert.isTrue(results[0].isMatch);
        Assert.isFalse(results[0].requiresEscalation);
        Assert.areEqual('Reconnect to campus WiFi', results[0].title);
        Assert.isTrue(results[0].resolutionSteps.contains('Forget the network'));
        Assert.isTrue(results[0].matchedKeywords.contains('wifi'));

        Assert.isTrue(results[1].isMatch);
        Assert.isTrue(results[1].requiresEscalation);
        Assert.isTrue(results[1].nextSteps.contains('escalate'));

        Assert.isFalse(results[2].isMatch);
        Assert.isTrue(results[2].requiresEscalation);

        Assert.isFalse(results[3].isMatch);
        Assert.isTrue(results[3].nextSteps.contains('description'));
    }

    @IsTest
    static void findGuide_emptyOrBlankReturnsSafely() {
        ITDeskSelfService.SelfServiceRequest blank = new ITDeskSelfService.SelfServiceRequest();
        blank.issueDescription = '   ';

        Test.startTest();
        List<ITDeskSelfService.SelfServiceResult> empty = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>()
        );
        List<ITDeskSelfService.SelfServiceResult> nullList = ITDeskSelfService.findGuide(null);
        List<ITDeskSelfService.SelfServiceResult> blankResult = ITDeskSelfService.findGuide(
            new List<ITDeskSelfService.SelfServiceRequest>{ blank }
        );
        Test.stopTest();

        Assert.areEqual(0, empty.size());
        Assert.areEqual(0, nullList.size());
        Assert.isFalse(blankResult[0].isMatch);
    }
}
