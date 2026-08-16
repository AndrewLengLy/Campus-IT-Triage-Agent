@IsTest
private class ITDeskDemoDataTest {
    @IsTest
    static void create_isIdempotent() {
        Test.startTest();
        List<Contact> first = ITDeskDemoData.create();
        List<Contact> second = ITDeskDemoData.create();
        Test.stopTest();

        Assert.areEqual(3, first.size());
        Assert.areEqual(3, second.size());
        Assert.areEqual(
            3,
            [
                SELECT COUNT()
                FROM Contact
                WHERE Student_ID__c IN :new Set<String>{
                    ITDeskDemoData.DEMO_ALEX,
                    ITDeskDemoData.DEMO_JORDAN,
                    ITDeskDemoData.DEMO_SAM
                }
            ]
        );
        Contact alex = [
            SELECT Email, LastName
            FROM Contact
            WHERE Student_ID__c = :ITDeskDemoData.DEMO_ALEX
        ];
        Assert.areEqual('alex.rivera@campus.edu', alex.Email);
        Assert.areEqual('Rivera', alex.LastName);
        Assert.isTrue(
            [
                SELECT COUNT()
                FROM Campus_IT_Interaction__c
                WHERE Student_ID__c IN :new Set<String>{
                    ITDeskDemoData.DEMO_ALEX,
                    ITDeskDemoData.DEMO_JORDAN,
                    ITDeskDemoData.DEMO_SAM
                }
            ] > 0,
            'First run should seed audit rows for the walkthrough.'
        );
    }
}
