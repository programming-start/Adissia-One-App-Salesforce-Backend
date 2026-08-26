/**
 * Author     : Sivam V
 * Class Name : AdissiaProjectDetails_MobileAPI
 * API Name   : AdissiaProjectDetails API
 * REST Method: GET
 * Purpose    : Details of a single project by Project Id (?projectId=P-0006).
 *              Returns: totalPlots, sitePlan (the "[ Phase Layout ]" file),
 *              brochure (the "[ Project Brochure ]" file), mapUrl (from geolocation),
 *              and amenities (from Amenity__c linked to the project, name + icon).
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/AdissiaProjectDetails/*')
global without sharing class AdissiaProjectDetails_MobileAPI {

    @HttpGet
    global static void getProjectDetails() {
        RestRequest request = RestContext.request;
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'AdissiaProjectDetails_MobileAPI';

        try {
            String projectId = request.params.get('projectId');
            apexLog.Request__c = 'projectId=' + projectId;

            if (String.isBlank(projectId)) {
                apexLog.response__c = 'Project Id should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Project Id should not be blank');
                return;
            }

            List<Project__c> projectList = [SELECT Id, Total_Units__c, Google_Map_Link__c FROM Project__c WHERE Project_Id__c = :projectId LIMIT 1];
            if (projectList.isEmpty()) {
                apexLog.response__c = 'No project found for this Project Id';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('No project found for this Project Id');
                return;
            }

            Project__c project = projectList[0];
            Set<Id> projectIdSet = new Set<Id>{ project.Id };

            // Files: site plan ([ Phase Layout ]) and brochure ([ Project Brochure ])
            Map<Id, String> sitePlanMap = getProjectFileUrl(projectIdSet, '[ Phase Layout ]');
            Map<Id, String> brochureMap = getProjectFileUrl(projectIdSet, '[ Project Brochure ]');

            // Amenities linked to the project (name + icon url)
            List<AmenityData> amenityList = new List<AmenityData>();
            for (Amenity__c amenity : [SELECT Id, Name, Amenity_Icon_Url__c FROM Amenity__c WHERE Project__c = :project.Id ORDER BY Name ASC]) {
                AmenityData amenityData = new AmenityData();
                amenityData.name = safe(amenity.Name);
                amenityData.iconUrl = safe(amenity.Amenity_Icon_Url__c);
                amenityList.add(amenityData);
            }

            ProjectDetailsData data = new ProjectDetailsData();
            data.totalPlots = project.Total_Units__c != null ? String.valueOf(project.Total_Units__c) : '0';
            data.sitePlan = sitePlanMap.containsKey(project.Id) ? sitePlanMap.get(project.Id) : '';
            data.brochure = brochureMap.containsKey(project.Id) ? brochureMap.get(project.Id) : '';
            data.mapUrl = safe(project.Google_Map_Link__c);
            data.amenities = amenityList;

            ProjectDetailsResponse response = new ProjectDetailsResponse();
            response.success = true;
            response.message = 'Project details fetched successfully';
            response.data = data;

            apexLog.response__c = 'Project details fetched successfully for ' + projectId;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    // Project Id -> download URL for the file whose title contains the given marker.
    // Returns the raw download URL (works for PDF/image site plans).
    private static Map<Id, String> getProjectFileUrl(Set<Id> projectIds, String titleMarker) {
        Map<Id, String> projectToFileUrl = new Map<Id, String>();
        if (projectIds.isEmpty()) { return projectToFileUrl; }

        List<ContentDocumentLink> documentLinks = [SELECT ContentDocumentId, LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :projectIds];

        Set<Id> contentDocumentIds = new Set<Id>();
        Map<Id, Id> documentToProject = new Map<Id, Id>();
        for (ContentDocumentLink link : documentLinks) {
            contentDocumentIds.add(link.ContentDocumentId);
            documentToProject.put(link.ContentDocumentId, link.LinkedEntityId);
        }
        if (contentDocumentIds.isEmpty()) { 
            return projectToFileUrl;
        }

        Map<Id, Id> versionToProject = new Map<Id, Id>();
        for (ContentVersion contentVersion : [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE IsLatest = TRUE AND ContentDocumentId IN :contentDocumentIds AND Title LIKE :('%' + titleMarker + '%')]) {
            Id relatedProjectId = documentToProject.get(contentVersion.ContentDocumentId);
            if (relatedProjectId != null) { versionToProject.put(contentVersion.Id, relatedProjectId); }
        }
        if (versionToProject.isEmpty()) { return projectToFileUrl; }

        for (ContentDistribution distribution : [SELECT ContentVersionId, ContentDownloadUrl FROM ContentDistribution WHERE ContentVersionId IN :versionToProject.keySet()]) {
            Id relatedProjectId = versionToProject.get(distribution.ContentVersionId);
            if (relatedProjectId != null && !projectToFileUrl.containsKey(relatedProjectId)) {
                projectToFileUrl.put(relatedProjectId, distribution.ContentDownloadUrl);
            }
        }
        return projectToFileUrl;
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // ----------------------------------------------------------------- WRAPPERS
    public class ProjectDetailsResponse {
        public Boolean success;
        public String message;
        public ProjectDetailsData data;
    }
    public class ProjectDetailsData {
        public String totalPlots;
        public String sitePlan;
        public String brochure;
        public String mapUrl;
        public List<AmenityData> amenities;
    }
    public class AmenityData {
        public String name;
        public String iconUrl;
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}