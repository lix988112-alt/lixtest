public with sharing class CRM_SalesShareAuditTool {
    public class AuditSummary {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public Integer totalShareRows;
        @AuraEnabled public Integer distinctParentRecords;

        public AuditSummary(String objectApiName, Integer totalShareRows, Integer distinctParentRecords) {
            this.objectApiName = objectApiName;
            this.totalShareRows = totalShareRows;
            this.distinctParentRecords = distinctParentRecords;
        }
    }

    @AuraEnabled(cacheable=true)
    public static AuditSummary auditByObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('objectApiName is required.');
        }

        String shareObject = objectApiName.endsWith('__c')
            ? objectApiName.replace('__c', '__Share')
            : objectApiName + 'Share';

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(shareObject)) {
            throw new AuraHandledException('No share table found for object: ' + objectApiName);
        }

        List<AggregateResult> totals = Database.query(
            'SELECT COUNT(Id) totalRows, COUNT_DISTINCT(ParentId) parentRows FROM ' + shareObject
        );

        Integer totalRows = 0;
        Integer parentRows = 0;

        if (!totals.isEmpty()) {
            totalRows = (Integer) totals[0].get('totalRows');
            parentRows = (Integer) totals[0].get('parentRows');
        }

        return new AuditSummary(objectApiName, totalRows, parentRows);
    }
}
