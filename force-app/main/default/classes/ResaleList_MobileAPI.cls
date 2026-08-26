@RestResource(urlMapping='/ResaleListAPI/*') // ResaleListAPI
global without sharing class ResaleList_MobileAPI {

    @HttpPost
    global static void getMyResaleDetail() {
        RestRequest req = RestContext.request;
        String requestBody = req.requestBody.toString(); // Get the JSON body
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c ='ResaleListAPI';
        log.Request__c = requestBody;

        try {
            ResalelistWrapper proj = (ResalelistWrapper) JSON.deserialize(requestBody, ResalelistWrapper.class);
            String userId = proj.userId;
            Boolean isMyResale = proj.isMyResale;
            decimal startPrice = proj.startPrice;
            decimal endPrice = proj.endPrice;
            String search = proj.search;
            String projectId = proj.projectId;
            String city = proj.city;
            decimal startArea = proj.startArea;
            decimal endArea = proj.endArea;
            decimal pageSize = proj.pageSize;
            decimal pageNumber = proj.pageNumber;

            if (String.isBlank(userId)  ) {
                log.response__c = 'UserId should not be blank';
                log.Status__c ='SUCCESS';
                insert log;
                sendErrorResponse('UserId should not be blank');
                return;
            }

            List<Customer_Master__c> cmList = [SELECT Id, Email__c, Password__c, First_Name__c, Last_Name__c, Phone__c, Name FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];

            if (cmList.isEmpty()) {
                log.response__c = 'Customer not found';
                log.Status__c = 'Success';
                insert log;
                sendErrorResponse('Customer not found ');
                return;
            }

            // isMyResale = TRUE  -> the person's PURCHASED PROPERTIES (Registration-completed bookings)
            // isMyResale = FALSE -> public FOR SALE list (Approved & Published resales of other users)
            if (isMyResale) {
                getMyPurchasedProperties(cmList[0].Id, log);
            } else {
                getPublicForSale(cmList[0].Id, proj, log);
            }
        }
        Catch(Exception e) {
            log.response__c = e.getStackTraceString();
            log.Status__c = 'FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            sendErrorResponse('Error: ' + e.getMessage());
        }
    }

    // ---------------------------------------------------------------- MY PURCHASED PROPERTIES
    // Registration-completed bookings of this customer, returned in the reSaleInfo shape.
    private static void getMyPurchasedProperties(Id customerRecordId, Apex_Log__c log) {
        List<Booking__c> bookingLst = [SELECT Id, Name, Plot__r.Name, Plot__r.Plot_Area_in_Cent__c, Plot__r.Project__c, Plot__r.Project__r.Project_Id__c, Plot__r.Project__r.Name, Plot__r.Project__r.Project_City__c, GRAND_TOTAL__c, Customer_Master__r.Phone__c FROM Booking__c WHERE Customer_Master__c = :customerRecordId AND Stage__c = 'Registration' AND Registration_Done__c = TRUE ORDER BY Booking_Date__c DESC];

        if (bookingLst.isEmpty()) {
            log.response__c = 'No Purchased Properties Found';
            log.Status__c = 'SUCCESS';
            insert log;
            sendErrorResponse('No Purchased Properties Found');
            return;
        }

        // Project images by project
        Set<Id> prjIds = new Set<Id>();
        Map<Id, Id> bookingToProject = new Map<Id, Id>();
        for (Booking__c bk : bookingLst) {
            if (bk.Plot__r != null && bk.Plot__r.Project__c != null) {
                prjIds.add(bk.Plot__r.Project__c);
                bookingToProject.put(bk.Id, bk.Plot__r.Project__c);
            }
        }
        Map<Id, List<String>> projectToImages = buildProjectImages(prjIds);

        ReSaleListResponse response = new ReSaleListResponse();
        response.success = true;
        response.message = 'Purchased Properties fetched Successfully';
        response.data = new ReSaleListData();
        response.data.resales = new List<reSaleInfo>();

        for (Booking__c bk : bookingLst) {
            reSaleInfo rsInfo = new reSaleInfo();
            rsInfo.resaleId = '';                                   // no resale record for a purchased property
            rsInfo.resalerContactNumber = bk.Customer_Master__r != null ? bk.Customer_Master__r.Phone__c : '';
            rsInfo.projectId = bk.Plot__r != null && bk.Plot__r.Project__r != null ? bk.Plot__r.Project__r.Project_Id__c : '';
            rsInfo.unitId = bk.Plot__r != null ? bk.Plot__r.Name : '';
            rsInfo.bookingId = bk.Name;
            rsInfo.projectName = bk.Plot__r != null && bk.Plot__r.Project__r != null ? bk.Plot__r.Project__r.Name : '';
            rsInfo.description = '';
            rsInfo.price = bk.GRAND_TOTAL__c;
            rsInfo.status = '';
            rsInfo.area = bk.Plot__r != null ? bk.Plot__r.Plot_Area_in_Cent__c : null;

            List<String> prjImages = new List<String>();
            Id projId = bookingToProject.get(bk.Id);
            if (projId != null && projectToImages.containsKey(projId)) {
                prjImages.addAll(projectToImages.get(projId));
            }
            rsInfo.projectImage = prjImages;
            response.data.resales.add(rsInfo);
        }

        log.response__c = 'Purchased Properties fetched Successfully';
        log.Status__c = 'SUCCESS';
        insert log;

        sendResponse(response);
    }

    // ---------------------------------------------------------------- PUBLIC FOR SALE (unchanged logic)
    private static void getPublicForSale(Id customerRecordId, ResalelistWrapper proj, Apex_Log__c log) {
        decimal startPrice = proj.startPrice;
        decimal endPrice = proj.endPrice;
        String search = proj.search;
        String projectId = proj.projectId;
        String city = proj.city;
        decimal startArea = proj.startArea;
        decimal endArea = proj.endArea;
        decimal pageSize = proj.pageSize;
        decimal pageNumber = proj.pageNumber;

        // Pagination inputs - default page size 20, default page 1
        Integer effectivePageSize = (pageSize != null && pageSize > 0) ? Integer.valueOf(pageSize) : 20;
        Integer effectivePageNumber = (pageNumber != null && pageNumber > 0) ? Integer.valueOf(pageNumber) : 1;
        Integer recordOffset = (effectivePageNumber - 1) * effectivePageSize;

        // Salesforce hard-caps SOQL OFFSET at 2000
        if (recordOffset > 2000) {
            log.response__c = 'Page range exceeded. Please refine your filters.';
            log.Status__c = 'SUCCESS';
            insert log;
            sendErrorResponse('Page range exceeded. Please refine your filters.');
            return;
        }

        List<Re_Sale_Property__c> rsLst = new List<Re_Sale_Property__c>();
        String query = 'SELECT Id, Name, Description__c, Seller_Price__c, Status__c, ' +
            'Booking__r.Plot__r.Project__r.Project_Id__c, Booking__r.Name, Booking__r.Plot__r.Plot_Area_in_Cent__c, ' +
            'Booking__c, Booking__r.Plot__r.Name, Booking__r.Plot__r.Project__c, Booking__r.Plot__r.Project__r.Name, ' +
            'Booking__r.Plot__r.Project__r.Project_City__c, ' +
            'Customer_Master__c, Customer_Master__r.Phone__c ' +
            'FROM Re_Sale_Property__c WHERE ';

        List<String> conditions = new List<String>();

        Id customerId = customerRecordId;
        conditions.add('Status__c = \'Approved & Published\'');
        conditions.add('Customer_Master__c != :customerId');

        if (startPrice != null && endPrice != null) {
            conditions.add('Seller_Price__c >= :startPrice AND Seller_Price__c <= :endPrice');
        }
        if (startArea != null && endArea != null) {
            conditions.add('Booking__r.Plot__r.Plot_Area_in_Cent__c >= :startArea AND Booking__r.Plot__r.Plot_Area_in_Cent__c <= :endArea');
        }
        if (String.isNotBlank(projectId)) {
            conditions.add('Booking__r.Plot__r.Project__r.Project_Id__c = :projectId');
        }
        if (String.isNotBlank(city)) {
            conditions.add('Booking__r.Plot__r.Project__r.Project_City__c = :city');
        }
        String searchPattern;
        if(String.isNotBlank(search)){
            searchPattern = '%' + search + '%';
            conditions.add('(Booking__r.Plot__r.Project__r.Name LIKE :searchPattern)');
        }

        query += String.join(conditions, ' AND ');
        query += ' ORDER BY CreatedDate DESC';
        query += ' LIMIT :effectivePageSize OFFSET :recordOffset';

        rsLst = Database.query(query);

        if (rsLst.isEmpty()) {
            log.response__c = 'Re-Sale Records Not Found';
            log.Status__c = 'SUCCESS';
            insert log;
            sendErrorResponse('Re-Sale Records Not Found');
            return;
        }

        Set<Id> PrjId = new Set<Id>();
        Map<Id,Id> ReSalePrjId = new Map<Id,Id>();
        for (Re_Sale_Property__c pr : rsLst) {
            PrjId.add(pr.Booking__r.Plot__r.Project__c);
            ReSalePrjId.put(pr.Id,pr.Booking__r.Plot__r.Project__c);
        }

        Map<Id, List<String>> docToDistUrlByProject = buildProjectImages(PrjId);

        ReSaleListResponse response = new ReSaleListResponse();
        response.success = true;
        response.message = 'Re-Sale List fetched Successfully';
        response.data = new ReSaleListData();
        response.data.resales = new List<reSaleInfo>();

        for (Re_Sale_Property__c rsp : rsLst) {
            reSaleInfo rsInfo = new reSaleInfo();
            rsInfo.resaleId = rsp.Name;
            rsInfo.resalerContactNumber = rsp.Customer_Master__r.Phone__c;
            rsInfo.projectId = rsp.Booking__r.Plot__r.Project__r.Project_Id__c;
            rsInfo.unitId = rsp.Booking__r.Plot__r.Name;
            rsInfo.bookingId = rsp.Booking__r.Name;
            rsInfo.projectName = rsp.Booking__r.Plot__r.Project__r.Name;
            rsInfo.description = rsp.Description__c;
            rsInfo.price = rsp.Seller_Price__c;
            rsInfo.status = rsp.Status__c;
            rsInfo.area = rsp.Booking__r.Plot__r.Plot_Area_in_Cent__c;

            List<String> prjImages = new List<String>();
            Id projId = ReSalePrjId.get(rsp.Id);
            if (projId != null && docToDistUrlByProject.containsKey(projId)) {
                prjImages.addAll(docToDistUrlByProject.get(projId));
            }
            rsInfo.projectImage = prjImages;
            response.data.resales.add(rsInfo);
        }

        sendResponse(response);
    }

    // Shared: project Id -> list of [ Project Image ] public URLs
    private static Map<Id, List<String>> buildProjectImages(Set<Id> prjIds) {
        Map<Id, List<String>> projectToImages = new Map<Id, List<String>>();
        if (prjIds == null || prjIds.isEmpty()) { return projectToImages; }

        List<ContentDocumentLink> docLinks = [ SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :prjIds ];

        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink link : docLinks) {
            contentDocIds.add(link.ContentDocumentId);
        }

        Map<Id, String> validDocTitles = new Map<Id, String>();
        for (ContentDocument doc : [ SELECT Id, Title FROM ContentDocument WHERE Id IN :contentDocIds AND Title LIKE '%[ Project Image ]%' ]) {
            validDocTitles.put(doc.Id, doc.Title);
        }

        Map<Id, List<String>> docToDistUrl = new Map<Id, List<String>>();
        for (ContentDistribution dist : [ SELECT ContentDocumentId, DistributionPublicUrl, ContentDownloadUrl FROM ContentDistribution WHERE ContentDocumentId IN :validDocTitles.keySet()]) {
            if (!docToDistUrl.containsKey(dist.ContentDocumentId))
                docToDistUrl.put(dist.ContentDocumentId, new List<String>());
            String picUrl = dist.ContentDownloadUrl.replace('download/?', 'renditionDownload?rendition=ORIGINAL_Jpg&').replace('&ids', '&versionId');
            docToDistUrl.get(dist.ContentDocumentId).add(picUrl);
        }

        for (ContentDocumentLink link : docLinks) {
            Id docId = link.ContentDocumentId;
            Id projId = link.LinkedEntityId;
            if (validDocTitles.containsKey(docId) && docToDistUrl.containsKey(docId)) {
                if (!projectToImages.containsKey(projId)) {
                    projectToImages.put(projId, new List<String>());
                }
                projectToImages.get(projId).addAll(docToDistUrl.get(docId));
            }
        }
        return projectToImages;
    }

    public class ResalelistWrapper {
        public String userId;
        public Boolean isMyResale;
        public decimal startPrice;
        public decimal endPrice;
        public String search;
        public String projectId;
        public string city;
        public decimal startArea;
        public decimal endArea;
        public decimal pageSize;
        public decimal pageNumber;
    }
    public class ReSaleListResponse {
        public Boolean success;
        public String message;
        public ReSaleListData data;
    }
    public class ReSaleListData {
        public List<reSaleInfo> resales;
    }

    public class reSaleInfo {
        public String resaleId;
        public String resalerContactNumber;
        public String projectId;
        public String bookingId;
        public String unitId;
        public String projectName;
        public List<String> projectImage;
        public String description;
        public Decimal price;
        public String status;
        public Decimal area;
    }
    private static void sendResponse(ReSaleListResponse response) {
        RestResponse res = RestContext.response;
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    private static void sendErrorResponse(String message) {
        ReSaleListResponse response = new ReSaleListResponse();
        response.success = false;
        response.message = message;

        RestResponse res = RestContext.response;
        res.statusCode = 400;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

}