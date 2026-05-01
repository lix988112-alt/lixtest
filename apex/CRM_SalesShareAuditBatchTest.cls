@IsTest
private class CRM_SalesShareAuditBatchTest {

    @IsTest
    static void testStartAllWithDefaultScope() {
        Test.startTest();
        Id jobId = CRM_SalesShareAuditBatch.startAll(null);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @IsTest
    static void testStartBySharingControlKeyWithCustomScope() {
        Test.startTest();
        Id jobId = CRM_SalesShareAuditBatch.startBySharingControlKey('DUMMY|CAT|USE', 1);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @IsTest
    static void testStartByProductCategoryAndUseWithInvalidScopeFallsBackToDefault() {
        Test.startTest();
        Id jobId = CRM_SalesShareAuditBatch.startByProductCategoryAndUse('Automotive', 'AutoIS', 0);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }
}
