/**
 * Author     : Sivam V
 * Class Name : AdissiaProjects_MobileAPI
 * API Name   : AdissiaProjects API
 * REST Method: GET
 * Purpose    : Return all Adissia projects (with a status). Per project sends:
 *              projectId, projectName, projectCity, availablePlots, status, projectImage.
 *              Also returns overall stats across all projects:
 *              totalProjects, totalHappyCustomers (all bookings),
 *              totalPlots (SUM Number_of_Plots__c), totalSquareFeet (SUM Total_Sq_ft__c).
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/AdissiaProjects/*')
global without sharing class AdissiaProjects_MobileAPI {

    @HttpGet
    global static void getAdissiaProjects() {
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'AdissiaProjects_MobileAPI';
        apexLog.Request__c = 'GET all projects';

        try {
            List<Project__c> projectList = [SELECT Id, Name, Project_Id__c, Project_City__c, Available_Units__c, Project_Status__c FROM Project__c WHERE Project_Status__c != NULL ORDER BY Name ASC];

            // Overall stats via aggregate queries (no looping - fast)
            Integer totalProjects = projectList.size();
            Integer totalHappyCustomers = [SELECT COUNT() FROM Booking__c];

            AggregateResult sums = [SELECT SUM(Total_Units__c) plots, SUM(Total_Sq_ft__c) sqft FROM Project__c WHERE Project_Status__c != NULL];
            Decimal totalPlots = (Decimal) sums.get('plots');
            Decimal totalSquareFeet = (Decimal) sums.get('sqft');

            Set<Id> projectIds = new Set<Id>();
            for (Project__c project : projectList) { projectIds.add(project.Id); }
            Map<Id, String> projectToImageUrl = getProjectImages(projectIds);

            List<ProjectData> projectDataList = new List<ProjectData>();
            for (Project__c project : projectList) {
                ProjectData projectData = new ProjectData();
                projectData.projectId = safe(project.Project_Id__c);
                projectData.projectName = safe(project.Name);
                projectData.projectCity = safe(project.Project_City__c);
                projectData.availablePlots = project.Available_Units__c != null ? String.valueOf(project.Available_Units__c) : '0';
                projectData.status = safe(project.Project_Status__c);
                projectData.projectImage = projectToImageUrl.containsKey(project.Id) ? projectToImageUrl.get(project.Id) : '';
                projectDataList.add(projectData);
            }

            ProjectsResponse response = new ProjectsResponse();
            response.success = true;
            response.message = 'Projects fetched successfully';
            response.data = new ProjectsData();
            response.data.projects = projectDataList;
            // Overall stats sit at the data level, not per project
            response.data.totalProjects = totalProjects;
            response.data.totalHappyCustomers = totalHappyCustomers;
            response.data.totalPlots = totalPlots != null ? Integer.valueOf(totalPlots) : 0;
            response.data.totalSquareFeet = totalSquareFeet != null ? String.valueOf(totalSquareFeet) : '0';

            apexLog.response__c = 'Projects fetched successfully';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            sendResponse(response);

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    // Project Id -> "[ Project Image ]" distribution URL, batched for all projects.
    private static Map<Id, String> getProjectImages(Set<Id> projectIds) {
        Map<Id, String> projectToImageUrl = new Map<Id, String>();
        if (projectIds.isEmpty()) { return projectToImageUrl; }

        List<ContentDocumentLink> documentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :projectIds];

        Set<Id> contentDocumentIds = new Set<Id>();
        Map<Id, Id> documentToProject = new Map<Id, Id>();
        for (ContentDocumentLink link : documentLinks) {
            contentDocumentIds.add(link.ContentDocumentId);
            documentToProject.put(link.ContentDocumentId, link.LinkedEntityId);
        }
        if (contentDocumentIds.isEmpty()) { return projectToImageUrl; }

        Map<Id, Id> versionToProject = new Map<Id, Id>();
        for (ContentVersion contentVersion : [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE IsLatest = TRUE AND ContentDocumentId IN :contentDocumentIds AND Title LIKE '%[ Project Image ]%']) {
            Id relatedProjectId = documentToProject.get(contentVersion.ContentDocumentId);
            if (relatedProjectId != null) { versionToProject.put(contentVersion.Id, relatedProjectId); }
        }
        if (versionToProject.isEmpty()) { return projectToImageUrl; }

        for (ContentDistribution distribution : [SELECT ContentVersionId, ContentDownloadUrl FROM ContentDistribution WHERE ContentVersionId IN :versionToProject.keySet()]) {
            Id relatedProjectId = versionToProject.get(distribution.ContentVersionId);
            if (relatedProjectId != null && !projectToImageUrl.containsKey(relatedProjectId)) {
                String imageUrl = distribution.ContentDownloadUrl.replace('download/?', 'renditionDownload?rendition=ORIGINAL_Jpg&').replace('&ids', '&versionId');
                projectToImageUrl.put(relatedProjectId, imageUrl);
            }
        }
        return projectToImageUrl;
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // ----------------------------------------------------------------- WRAPPERS
    public class ProjectsResponse {
        public Boolean success;
        public String message;
        public ProjectsData data;
    }
    public class ProjectsData {
        public List<ProjectData> projects;
        public Integer totalProjects;
        public Integer totalHappyCustomers;
        public Integer totalPlots;
        public String totalSquareFeet;
    }
    public class ProjectData {
        public String projectId;
        public String projectName;
        public String projectCity;
        public String availablePlots;
        public String status;
        public String projectImage;
    }

    private static void sendResponse(ProjectsResponse response) {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}