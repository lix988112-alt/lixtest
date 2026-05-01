/**
 * Case / Escalation の販社共有（A/C/D共有）の整合性を監査するツールクラス
 * @author SGS lixiang 2026/04/03
 */
global without sharing class CRM_SalesShareAuditBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final String RT_EXCEPTION = 'Exception';
    private static final String RT_NORMAL = 'Normal';
    private static final String ACCESS_READ = 'Read';
    private static final String ROW_CAUSE_MANUAL = 'Manual';
    private static final String OBJ_CASE = 'Case';
    private static final String OBJ_ESCALATION = 'Escalation__c';

    global String sharingControlKey;
    global String productCategory;
    global String productUse;

    global Integer totalCaseCount = 0;
    global Integer correctCaseCount = 0;
    global Integer wrongCaseCount = 0;
    global Integer totalEscalationCount = 0;
    global Integer correctEscalationCount = 0;
    global Integer wrongEscalationCount = 0;

    // 監査結果（全体）
    public class AuditResult {
        // 監査対象の SharingControlKey__c（全件監査時は null）
        public String sharingControlKey;
        // 監査対象の ProductCategory__c
        public String productCategory;
        // 監査対象の ProductUse__c
        public String productUse;
        // 監査対象となった Case 総件数
        public Integer totalCaseCount = 0;
        // 共有状態が正しい Case 件数
        public Integer correctCaseCount = 0;
        // 共有状態が誤っている Case 件数
        public Integer wrongCaseCount = 0;
        // 監査対象となった Escalation 総件数
        public Integer totalEscalationCount = 0;
        // 共有状態が正しい Escalation 件数
        public Integer correctEscalationCount = 0;
        // 共有状態が誤っている Escalation 件数
        public Integer wrongEscalationCount = 0;
        // 誤りがある Case の明細一覧
        public List<RecordAuditResult> caseResults = new List<RecordAuditResult>();
        // 誤りがある Escalation の明細一覧
        public List<RecordAuditResult> escalationResults = new List<RecordAuditResult>();
    }

    // 監査結果（1レコード単位）
    public class RecordAuditResult {
        // オブジェクト API 名（Case / Escalation__c）
        public String objectApiName;
        // レコード ID
        public Id recordId;
        // レコード表示名（CaseNumber / Name）
        public String recordName;
        // 当該レコードに紐づく SharingControlKey__c
        public String sharingControlKey;
        // D共有（ExceptionFlag__c）が有効かどうか
        public Boolean manualExceptionEnabled;
        // 共有状態が期待値どおりかどうか
        public Boolean correct;
        // 期待される共有先 Public Group 一覧
        public List<String> expectedGroups = new List<String>();
        // 実際に設定されている共有先 Public Group 一覧
        public List<String> actualGroups = new List<String>();
        // 本来あるべきだが不足している Public Group 一覧
        public List<String> missingGroups = new List<String>();
        // 本来不要だが余分に存在している Public Group 一覧
        public List<String> extraGroups = new List<String>();
        // 監査時に検知した設定上の注意点・警告
        public List<String> warnings = new List<String>();
    }

    // 監査用の共通コンテキスト
    private class AuditContext {
        public Map<Id, Case> caseMap = new Map<Id, Case>();
        public Map<Id, Escalation__c> escalationMap = new Map<Id, Escalation__c>();
        public Map<Id, List<Case_Manual_Share__c>> caseManualNormals = new Map<Id, List<Case_Manual_Share__c>>();
        public Set<Id> manualOnCaseIds = new Set<Id>();
        public Map<Id, List<EscalationManualShare__c>> escalationManualNormals = new Map<Id, List<EscalationManualShare__c>>();
        public Set<Id> manualOnEscalationIds = new Set<Id>();
        public Map<Id, Set<Id>> actualCaseShareGroupIds = new Map<Id, Set<Id>>();
        public Map<Id, Set<Id>> actualEscalationShareGroupIds = new Map<Id, Set<Id>>();
        public Map<String, SharingControl2__c> keyToSharingControl = new Map<String, SharingControl2__c>();
        public Map<String, Set<String>> sourceToTargetKeys = new Map<String, Set<String>>();
        public Map<String, String> targetKeyToGroupDevName = new Map<String, String>();
        public Map<String, Id> targetKeyToGroupId = new Map<String, Id>();
        public Map<Id, String> groupIdToDevName = new Map<Id, String>();
        public Set<Id> allowedCaseIds = new Set<Id>();
    }


    // 全件監査用コンストラクタ
    global CRM_SalesShareAuditBatch() {
    }

    /**
     * SharingControlKey__c 指定監査用コンストラクタ
     * @param sharingControlKey 共有制御キー
     */
    global CRM_SalesShareAuditBatch(String sharingControlKey) {
        this.sharingControlKey = sharingControlKey;
    }

    /**
     * ProductCategory__c / ProductUse__c 指定監査用コンストラクタ
     * @param productCategory 製品カテゴリ
     * @param productUse      製品用途
     */
    global CRM_SalesShareAuditBatch(String productCategory, String productUse) {
        this.productCategory = productCategory;
        this.productUse = productUse;
    }

    /**
     * 全件監査 Batch を起動する。
     * @param scopeSize scope 件数
     */
    global static Id startAll(Integer scopeSize) {
        return Database.executeBatch(new CRM_SalesShareAuditBatch(), getScopeSize(scopeSize));
    }

    /**
     * SharingControlKey__c 指定監査 Batch を起動する。
     * @param sharingControlKey 共有制御キー
     * @param scopeSize         scope 件数
     */
    global static Id startBySharingControlKey(String sharingControlKey, Integer scopeSize) {
        return Database.executeBatch(new CRM_SalesShareAuditBatch(sharingControlKey), getScopeSize(scopeSize));
    }

    /**
     * ProductCategory__c / ProductUse__c 指定監査 Batch を起動する。
     * @param productCategory 製品カテゴリ
     * @param productUse      製品用途
     * @param scopeSize       scope 件数
     */
    global static Id startByProductCategoryAndUse(String productCategory, String productUse, Integer scopeSize) {
        return Database.executeBatch(new CRM_SalesShareAuditBatch(productCategory, productUse), getScopeSize(scopeSize));
    }

    /**
     * Batch 開始処理、Case を起点に対象レコードを取得する。
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {

        Id caseRecordTypeId = CRM_CommonRecordTypeUtils.getRecordTypeIdByObjectNameAndDeveloperName(
            'Case', System.Label.CRM_CASE_RECORDTYPE_DEVNAME_CS);

        String soql = 'SELECT Id FROM Case';

        List<String> conditions = new List<String>();
        conditions.add('RecordTypeId = :caseRecordTypeId');
        // conditions.add('Origin != \'Mail2Case\'');

        if (String.isNotBlank(sharingControlKey)) {
            conditions.add('SharingControlKey__c = :sharingControlKey');
        } else if (String.isNotBlank(productCategory) || String.isNotBlank(productUse)) {
            conditions.add('ProductCategory__c = :productCategory');
            conditions.add('ProductUse__c = :productUse');
        }

        if (!conditions.isEmpty()) {
            soql += ' WHERE ' + String.join(conditions, ' AND ');
        }
        if (Test.isRunningTest()) {
            soql += ' LIMIT 50';
        }

        return Database.getQueryLocator(soql);
    }

    /**
     * Batch 実行処理、scope 内の Case と、その Case に紐づく Escalation を監査する。
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {

        Set<Id> caseIds = new Set<Id>();
        for (SObject row : scope) {
            caseIds.add((Id)row.get('Id'));
        }

        if (caseIds.isEmpty()) {
            return;
        }

        AuditResult result = checkByCaseIds(caseIds);

        totalCaseCount += result.totalCaseCount;
        correctCaseCount += result.correctCaseCount;
        wrongCaseCount += result.wrongCaseCount;
        totalEscalationCount += result.totalEscalationCount;
        correctEscalationCount += result.correctEscalationCount;
        wrongEscalationCount += result.wrongEscalationCount;

        if (!result.caseResults.isEmpty() || !result.escalationResults.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'CRM_SalesShareAuditBatch scope mismatch result = ' + JSON.serializePretty(result));
        }
    }

    /**
     * Batch 終了処理、集計結果をログ出力する。
     */
    global void finish(Database.BatchableContext bc) {

        Map<String, Object> summary = new Map<String, Object>{
            '誤りエスカレーション数' => wrongEscalationCount,
            '正解エスカレーション数' => correctEscalationCount,
            'エスカレーション総数' => totalEscalationCount,
            '誤りケース数' => wrongCaseCount,
            '正解ケース数' => correctCaseCount,
            'ケース総数' => totalCaseCount,
            '製品用途' => productUse,
            '製品カテゴリ' => productCategory,
            '共有制御キー' => sharingControlKey
        };

        System.debug(LoggingLevel.WARN,'CRM_SalesShareAuditBatch finish summary = ' + JSON.serializePretty(summary)
        );
    }

    // 指定した Case 一覧を対象に監査する。Batch 実行時の scope 単位判定で使用する。
    private static AuditResult checkByCaseIds(Set<Id> caseIds) {
        return checkByCaseIds(caseIds, null, null, null);
    }

    /**
     * 指定した Case 一覧を対象に監査する。
     * scope 内の Case と、その Case に紐づく Escalation を対象に監査する。
     * @param caseIds            対象CaseID一覧
     * @param sharingControlKey  共有制御キー
     * @param productCategory    製品カテゴリ
     * @param productUse         製品用途
     */
    private static AuditResult checkByCaseIds(Set<Id> caseIds, String sharingControlKey, String productCategory, String productUse) {

        AuditResult result = new AuditResult();
        result.sharingControlKey = sharingControlKey;
        result.productCategory = productCategory;
        result.productUse = productUse;

        AuditContext ctx = buildContextByCaseIds(caseIds);

        for (Case ca : ctx.caseMap.values()) {
            RecordAuditResult item = auditCase(ca, ctx);
            result.totalCaseCount++;
            if (item.correct) {
                result.correctCaseCount++;
            } else {
                result.wrongCaseCount++;
                result.caseResults.add(item);
            }
        }

        for (Escalation__c esc : ctx.escalationMap.values()) {
            RecordAuditResult item = auditEscalation(esc, ctx);
            result.totalEscalationCount++;
            if (item.correct) {
                result.correctEscalationCount++;
            } else {
                result.wrongEscalationCount++;
                result.escalationResults.add(item);
            }
        }

        return result;
    }

    // 指定した Case 一覧を対象に監査用データを読み込む。
    private static AuditContext buildContextByCaseIds(Set<Id> caseIds) {

        AuditContext ctx = new AuditContext();

        ctx.caseMap = queryCasesByIds(caseIds);
        ctx.escalationMap = queryEscalationsByCaseIds(caseIds);

        // Case の手動共有情報
        loadCaseManualShares(ctx);
        // Escalation の手動共有情報
        loadEscalationManualShares(ctx);
        // A/C/D の共有マッピング
        loadSharingMetadata(ctx);
        // 実際の CaseShare / Escalation__Share
        loadActualShares(ctx);
        // A/C 共有の判定結果
        loadAllowedCases(ctx);

        return ctx;
    }

    // 指定した Case 一覧を取得する。
    private static Map<Id, Case> queryCasesByIds(Set<Id> caseIds) {

        if (caseIds == null || caseIds.isEmpty()) {
            return new Map<Id, Case>();
        }

        Id caseRecordTypeId = CRM_CommonRecordTypeUtils.getRecordTypeIdByObjectNameAndDeveloperName('Case', System.Label.CRM_CASE_RECORDTYPE_DEVNAME_CS);

        return new Map<Id, Case>([
            SELECT Id,CaseNumber,IsPrivate__c,CaseSalesCompany__c,ProductCategory__c,ProductUse__c,SharingControlKey__c,
                    AccountId,SpecifiedAgency_AccountName__c,EndCustomer__r.EndCustomer__c,
                    ProductOfficialName1__c,ProductOfficialName2__c,ProductOfficialName3__c,ProductOfficialName4__c,
                    RequestCategory__c,RequestCategoryDetail__c
            FROM Case
            WHERE Id IN :caseIds
              AND RecordTypeId = :caseRecordTypeId
            //   AND Origin != 'Mail2Case'
              AND CaseSalesCompany__c != null
        ]);
    }

    // 指定した Case 一覧に紐づく Escalation を取得する。
    private static Map<Id, Escalation__c> queryEscalationsByCaseIds(Set<Id> caseIds) {

        if (caseIds == null || caseIds.isEmpty()) {
            return new Map<Id, Escalation__c>();
        }

        return new Map<Id, Escalation__c>([
            SELECT Id,Name,SalesComPrivateFlag__c,CaseSalesCompany__c,ProductCategory__c,ProductUse__c,CaseNum__c,CaseNum__r.SharingControlKey__c
            FROM Escalation__c
            WHERE CaseNum__c IN :caseIds
            //   AND CaseNum__r.Origin != 'Mail2Case'
        ]);
    }

    // Case の手動共有情報を取得する。
    // Exception レコードは D共有ON/OFF 判定に使用し、Normal レコードは D共有ON時の期待値算出に使用する。
    private static void loadCaseManualShares(AuditContext ctx) {

        if (ctx.caseMap.isEmpty()) {
            return;
        }

        for (Case_Manual_Share__c rec : [
            SELECT Id,Case__c,TargetSalesCompany__c,IsShared__c,ExceptionFlag__c,RecordType.DeveloperName
            FROM Case_Manual_Share__c
            WHERE Case__c IN :ctx.caseMap.keySet()
        ]) {
            if (rec.RecordType.DeveloperName == RT_EXCEPTION && rec.ExceptionFlag__c == true) {
                ctx.manualOnCaseIds.add(rec.Case__c);
                continue;
            }

            if (rec.RecordType.DeveloperName != RT_NORMAL) {
                continue;
            }

            if (!ctx.caseManualNormals.containsKey(rec.Case__c)) {
                ctx.caseManualNormals.put(rec.Case__c, new List<Case_Manual_Share__c>());
            }
            ctx.caseManualNormals.get(rec.Case__c).add(rec);
        }
    }

    // Escalation の手動共有情報を取得する。
    private static void loadEscalationManualShares(AuditContext ctx) {

        if (ctx.escalationMap.isEmpty()) {
            return;
        }

        for (EscalationManualShare__c rec : [
            SELECT Id,Escalation__c,TargetSalesCompany__c,IsShared__c,ExceptionFlag__c,RecordType.DeveloperName
            FROM EscalationManualShare__c
            WHERE Escalation__c IN :ctx.escalationMap.keySet()
        ]) {
            if (rec.RecordType.DeveloperName == RT_EXCEPTION && rec.ExceptionFlag__c == true) {
                ctx.manualOnEscalationIds.add(rec.Escalation__c);
                continue;
            }

            if (rec.RecordType.DeveloperName != RT_NORMAL) {
                continue;
            }

            if (!ctx.escalationManualNormals.containsKey(rec.Escalation__c)) {
                ctx.escalationManualNormals.put(rec.Escalation__c, new List<EscalationManualShare__c>());
            }
            ctx.escalationManualNormals.get(rec.Escalation__c).add(rec);
        }
    }

    // 共有判定に必要なマスタ情報を取得する。
    private static void loadSharingMetadata(AuditContext ctx) {

        Set<String> sourceKeys = new Set<String>();
        Set<String> targetKeys = new Set<String>();

        for (Case ca : ctx.caseMap.values()) {
            if (String.isNotBlank(ca.SharingControlKey__c)) {
                sourceKeys.add(ca.SharingControlKey__c);
            }
        }

        for (Escalation__c esc : ctx.escalationMap.values()) {
            if (esc.CaseNum__r != null && String.isNotBlank(esc.CaseNum__r.SharingControlKey__c)) {
                sourceKeys.add(esc.CaseNum__r.SharingControlKey__c);
            }
        }

        for (SharingControl2__c shr : [
            SELECT Id,SharingControlKey__c,ProductCategory__c,ProductUse__c
            FROM SharingControl2__c
            WHERE SharingControlKey__c IN :sourceKeys
        ]) {
            ctx.keyToSharingControl.put(shr.SharingControlKey__c, shr);
        }

        for (SharingControl2Detail__c detail : [
            SELECT SharingControlKey__c, SharingControlKeyTarget__c
            FROM SharingControl2Detail__c
            WHERE SharingControlKey__c IN :sourceKeys
        ]) {
            if (!ctx.sourceToTargetKeys.containsKey(detail.SharingControlKey__c)) {
                ctx.sourceToTargetKeys.put(detail.SharingControlKey__c, new Set<String>());
            }
            ctx.sourceToTargetKeys.get(detail.SharingControlKey__c).add(detail.SharingControlKeyTarget__c);
            targetKeys.add(detail.SharingControlKeyTarget__c);
        }

        for (Case ca : ctx.caseMap.values()) {
            addManualTargetKeysForCase(ca, ctx, targetKeys);
        }
        for (Escalation__c esc : ctx.escalationMap.values()) {
            addManualTargetKeysForEscalation(esc, ctx, targetKeys);
        }

        if (targetKeys.isEmpty()) {
            return;
        }

        for (SharingGroupMapping__c mapping : [
            SELECT SharingControlKey__c, SharedPublicGroup__c
            FROM SharingGroupMapping__c
            WHERE SharingControlKey__c IN :targetKeys
        ]) {
            ctx.targetKeyToGroupDevName.put(mapping.SharingControlKey__c, mapping.SharedPublicGroup__c);
        }

        Set<String> groupDevNames = new Set<String>(ctx.targetKeyToGroupDevName.values());
        if (groupDevNames.isEmpty()) {
            return;
        }

        Map<String, Id> groupDevNameToId = new Map<String, Id>();
        for (Group grp : [
            SELECT Id, DeveloperName
            FROM Group
            WHERE DeveloperName IN :groupDevNames
        ]) {
            groupDevNameToId.put(grp.DeveloperName, grp.Id);
            ctx.groupIdToDevName.put(grp.Id, grp.DeveloperName);
        }

        for (String targetKey : ctx.targetKeyToGroupDevName.keySet()) {
            String devName = ctx.targetKeyToGroupDevName.get(targetKey);
            if (groupDevNameToId.containsKey(devName)) {
                ctx.targetKeyToGroupId.put(targetKey, groupDevNameToId.get(devName));
            }
        }
    }

    // Case の D共有 Normal レコードから対象 target key を収集する。
    private static void addManualTargetKeysForCase(Case ca, AuditContext ctx, Set<String> targetKeys) {
        if (!ctx.caseManualNormals.containsKey(ca.Id)) {
            return;
        }
        for (Case_Manual_Share__c rec : ctx.caseManualNormals.get(ca.Id)) {
            if (rec.IsShared__c == true && String.isNotBlank(rec.TargetSalesCompany__c)) {
                targetKeys.add(buildTargetKey(rec.TargetSalesCompany__c, ca.ProductCategory__c, ca.ProductUse__c));
            }
        }
    }

    // Escalation の D共有 Normal レコードから対象 target key を収集する。
    private static void addManualTargetKeysForEscalation(Escalation__c esc, AuditContext ctx, Set<String> targetKeys) {
        if (!ctx.escalationManualNormals.containsKey(esc.Id)) {
            return;
        }
        for (EscalationManualShare__c rec : ctx.escalationManualNormals.get(esc.Id)) {
            if (rec.IsShared__c == true && String.isNotBlank(rec.TargetSalesCompany__c)) {
                targetKeys.add(buildTargetKey(rec.TargetSalesCompany__c, esc.ProductCategory__c, esc.ProductUse__c));
            }
        }
    }

    // 実際に作成されている本機能対象の共有を取得する。
    // Manual / Read の share のみを監査対象とする。
    private static void loadActualShares(AuditContext ctx) {

        Set<Id> targetGroupIds = new Set<Id>(ctx.targetKeyToGroupId.values());
        if (targetGroupIds.isEmpty()) {
            return;
        }

        if (!ctx.caseMap.isEmpty()) {
            for (CaseShare rec : [
                SELECT CaseId, UserOrGroupId
                FROM CaseShare
                WHERE CaseId IN :ctx.caseMap.keySet()
                  AND RowCause = :ROW_CAUSE_MANUAL
                  AND CaseAccessLevel = :ACCESS_READ
                  AND UserOrGroupId IN :targetGroupIds
            ]) {
                if (!ctx.actualCaseShareGroupIds.containsKey(rec.CaseId)) {
                    ctx.actualCaseShareGroupIds.put(rec.CaseId, new Set<Id>());
                }
                ctx.actualCaseShareGroupIds.get(rec.CaseId).add(rec.UserOrGroupId);
            }
        }

        if (!ctx.escalationMap.isEmpty()) {
            for (Escalation__Share rec : [
                SELECT ParentId, UserOrGroupId
                FROM Escalation__Share
                WHERE ParentId IN :ctx.escalationMap.keySet()
                  AND RowCause = :ROW_CAUSE_MANUAL
                  AND AccessLevel = :ACCESS_READ
                  AND UserOrGroupId IN :targetGroupIds
            ]) {
                if (!ctx.actualEscalationShareGroupIds.containsKey(rec.ParentId)) {
                    ctx.actualEscalationShareGroupIds.put(rec.ParentId, new Set<Id>());
                }
                ctx.actualEscalationShareGroupIds.get(rec.ParentId).add(rec.UserOrGroupId);
            }
        }
    }

    // A/C 共有の判定結果として、実際に共有対象となる Case を算出する。
    // 既存の CRM_SharingControl2ABatch.queryTargetCases をそのまま利用し、本番ロジックとの差異を避ける。
    private static void loadAllowedCases(AuditContext ctx) {

        Map<String, Set<Id>> keyToCaseIds = new Map<String, Set<Id>>();
        for (Case ca : ctx.caseMap.values()) {
            if (String.isBlank(ca.SharingControlKey__c)) {
                continue;
            }
            if (!ctx.keyToSharingControl.containsKey(ca.SharingControlKey__c)) {
                continue;
            }
            if (!keyToCaseIds.containsKey(ca.SharingControlKey__c)) {
                keyToCaseIds.put(ca.SharingControlKey__c, new Set<Id>());
            }
            keyToCaseIds.get(ca.SharingControlKey__c).add(ca.Id);
        }

        for (String key : keyToCaseIds.keySet()) {
            SharingControl2__c shrCtl = ctx.keyToSharingControl.get(key);
            for (Case allowedCase : CRM_SharingControl2ABatch.queryTargetCases(shrCtl, keyToCaseIds.get(key))) {
                ctx.allowedCaseIds.add(allowedCase.Id);
            }
        }
    }

    // 1件の Case を監査する。
    private static RecordAuditResult auditCase(Case ca, AuditContext ctx) {

        RecordAuditResult item = new RecordAuditResult();
        item.objectApiName = OBJ_CASE;
        item.recordId = ca.Id;
        item.recordName = ca.CaseNumber;
        item.sharingControlKey = ca.SharingControlKey__c;
        item.manualExceptionEnabled = ctx.manualOnCaseIds.contains(ca.Id);

        Set<Id> expectedGroupIds = new Set<Id>();
        if (item.manualExceptionEnabled) {
            // D共有ONの Case に対する期待 share を算出する。
            expectedGroupIds = getExpectedManualCaseGroupIds(ca, ctx, item.warnings);
        } else {
            // Case に対する期待 share を算出する。
            expectedGroupIds = getExpectedSystemCaseGroupIds(ca, ctx, item.warnings);
        }

        // 実際の共有
        Set<Id> actualGroupIds = ctx.actualCaseShareGroupIds.containsKey(ca.Id)
            ? ctx.actualCaseShareGroupIds.get(ca.Id)
            : new Set<Id>();

        fillComparison(item, expectedGroupIds, actualGroupIds, ctx);
        return item;
    }


    // 1件の Escalation を監査する。
    private static RecordAuditResult auditEscalation(Escalation__c esc, AuditContext ctx) {

        RecordAuditResult item = new RecordAuditResult();
        item.objectApiName = OBJ_ESCALATION;
        item.recordId = esc.Id;
        item.recordName = esc.Name;
        item.sharingControlKey = esc.CaseNum__r == null ? null : esc.CaseNum__r.SharingControlKey__c;
        item.manualExceptionEnabled = ctx.manualOnEscalationIds.contains(esc.Id);

        Set<Id> expectedGroupIds = new Set<Id>();
        if (item.manualExceptionEnabled) {
            expectedGroupIds = getExpectedManualEscalationGroupIds(esc, ctx, item.warnings);
        } else {
            expectedGroupIds = getExpectedSystemEscalationGroupIds(esc, ctx, item.warnings);
        }

        Set<Id> actualGroupIds = ctx.actualEscalationShareGroupIds.containsKey(esc.Id)
            ? ctx.actualEscalationShareGroupIds.get(esc.Id)
            : new Set<Id>();

        fillComparison(item, expectedGroupIds, actualGroupIds, ctx);
        return item;
    }

    // D共有ONの Case に対する期待 share を算出する。
    // Case_Manual_Share__c の Normal レコードで、IsShared__c = true の販社のみ共有対象とする。
    private static Set<Id> getExpectedManualCaseGroupIds(Case ca, AuditContext ctx, List<String> warnings) {
        Set<Id> result = new Set<Id>();

        if (!ctx.caseManualNormals.containsKey(ca.Id)) {
            warnings.add('Manual override is enabled, but no Case_Manual_Share__c Normal rows were found.');
            return result;
        }

        for (Case_Manual_Share__c rec : ctx.caseManualNormals.get(ca.Id)) {
            if (rec.IsShared__c != true || String.isBlank(rec.TargetSalesCompany__c)) {
                continue;
            }

            String targetKey = buildTargetKey(rec.TargetSalesCompany__c, ca.ProductCategory__c, ca.ProductUse__c);
            Id groupId = ctx.targetKeyToGroupId.get(targetKey);
            if (groupId == null) {
                warnings.add('No Public Group mapping found for Case manual target key: ' + targetKey);
                continue;
            }
            result.add(groupId);
        }

        return result;
    }

    // D共有OFFの Case に対する期待 share を算出する。
    // A共有対象かつ C非共有条件に該当しない Case のみ、SharingControl2Detail__c に基づいて共有対象とする。
    private static Set<Id> getExpectedSystemCaseGroupIds(Case ca,AuditContext ctx,List<String> warnings) {
        Set<Id> result = new Set<Id>();

        if (ca.IsPrivate__c == true) {
            return result;
        }
        if (String.isBlank(ca.SharingControlKey__c)) {
            return result;
        }
        if (!ctx.allowedCaseIds.contains(ca.Id)) {
            return result;
        }
        if (!ctx.sourceToTargetKeys.containsKey(ca.SharingControlKey__c)) {
            return result;
        }

        for (String targetKey : ctx.sourceToTargetKeys.get(ca.SharingControlKey__c)) {
            Id groupId = ctx.targetKeyToGroupId.get(targetKey);
            if (groupId == null) {
                warnings.add('No Public Group mapping found for A/C target key: ' + targetKey);
                continue;
            }
            result.add(groupId);
        }

        return result;
    }

    // D共有ONの Escalation に対する期待 share を算出する。
    private static Set<Id> getExpectedManualEscalationGroupIds(Escalation__c esc, AuditContext ctx, List<String> warnings) {
        Set<Id> result = new Set<Id>();

        if (!ctx.escalationManualNormals.containsKey(esc.Id)) {
            warnings.add('Manual override is enabled, but no EscalationManualShare__c Normal rows were found.');
            return result;
        }

        for (EscalationManualShare__c rec : ctx.escalationManualNormals.get(esc.Id)) {
            if (rec.IsShared__c != true || String.isBlank(rec.TargetSalesCompany__c)) {
                continue;
            }

            String targetKey = buildTargetKey(rec.TargetSalesCompany__c, esc.ProductCategory__c, esc.ProductUse__c);
            Id groupId = ctx.targetKeyToGroupId.get(targetKey);
            if (groupId == null) {
                warnings.add('No Public Group mapping found for Escalation manual target key: ' + targetKey);
                continue;
            }
            result.add(groupId);
        }

        return result;
    }

    // D共有OFFの Escalation に対する期待 share を算出する。
    // 親Case が A/C 共有対象であることを前提に、親Case の SharingControlKey__c から共有先を判定する。
    private static Set<Id> getExpectedSystemEscalationGroupIds(Escalation__c esc, AuditContext ctx, List<String> warnings) {
        Set<Id> result = new Set<Id>();

        if (esc.SalesComPrivateFlag__c == 'True') {
            return result;
        }
        if (esc.CaseNum__c == null || esc.CaseNum__r == null || String.isBlank(esc.CaseNum__r.SharingControlKey__c)) {
            return result;
        }
        if (!ctx.allowedCaseIds.contains(esc.CaseNum__c)) {
            return result;
        }
        if (!ctx.sourceToTargetKeys.containsKey(esc.CaseNum__r.SharingControlKey__c)) {
            return result;
        }

        for (String targetKey : ctx.sourceToTargetKeys.get(esc.CaseNum__r.SharingControlKey__c)) {
            Id groupId = ctx.targetKeyToGroupId.get(targetKey);
            if (groupId == null) {
                warnings.add('No Public Group mapping found for A/C target key: ' + targetKey);
                continue;
            }
            result.add(groupId);
        }

        return result;
    }

    // 期待値と実値を比較し、差分結果を格納する。
    private static void fillComparison(
        RecordAuditResult item,
        Set<Id> expectedGroupIds,
        Set<Id> actualGroupIds,
        AuditContext ctx
    ) {
        Set<Id> missingGroupIds = new Set<Id>(expectedGroupIds);
        missingGroupIds.removeAll(actualGroupIds);

        Set<Id> extraGroupIds = new Set<Id>(actualGroupIds);
        extraGroupIds.removeAll(expectedGroupIds);

        item.expectedGroups = toSortedGroupNames(expectedGroupIds, ctx);
        item.actualGroups = toSortedGroupNames(actualGroupIds, ctx);
        item.missingGroups = toSortedGroupNames(missingGroupIds, ctx);
        item.extraGroups = toSortedGroupNames(extraGroupIds, ctx);
        item.correct = missingGroupIds.isEmpty() && extraGroupIds.isEmpty();
    }

    // GroupId の集合を、表示用の DeveloperName 一覧へ変換する。
    private static List<String> toSortedGroupNames(Set<Id> groupIds, AuditContext ctx) {
        List<String> result = new List<String>();
        for (Id groupId : groupIds) {
            String name = ctx.groupIdToDevName.containsKey(groupId)
                ? ctx.groupIdToDevName.get(groupId)
                : String.valueOf(groupId);
            result.add(name);
        }
        result.sort();
        return result;
    }

    // 販社 + ProductCategory + ProductUse から target key を生成する。
    private static String buildTargetKey(String targetSalesCompany, String productCategory, String productUse) {
        return String.valueOf(targetSalesCompany) + '|' + String.valueOf(productCategory) + '|' + String.valueOf(productUse);
    }

    /**
     * scope件数のデフォルト値を補正する。
     * @param scopeSize 指定scope件数
     */
    private static Integer getScopeSize(Integer scopeSize) {
        return (scopeSize == null || scopeSize <= 0) ? 200 : scopeSize;
    }
//CRM_SalesShareAuditBatch.startAll(200);
//CRM_SalesShareAuditBatch.startBySharingControlKey('SSS|Automotive|AutoIS', 200);
//CRM_SalesShareAuditBatch.startByProductCategoryAndUse('Automotive', 'AutoIS', 200);
}