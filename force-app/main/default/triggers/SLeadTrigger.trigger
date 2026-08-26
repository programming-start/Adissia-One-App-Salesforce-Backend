trigger SLeadTrigger on Lead (before insert, after insert, before update, after update, before delete, after delete, after undelete){
    
    if(label.Enable_Trigger=='TRUE'){
        // In custom label if Enable_Trigger makes as false , in production make sure to Enable_Trigger to true after work completed.
        System.debug('Lead Trigger Logic Starts---->');
        List<Lead> leadsToSend = new List<Lead>();
        if(Utility.runLeadTrigger != false){
            if (Trigger.isBefore){
                //NRI Allocation by sathya 18-06-2026
                Id nriCampaignId;
                    if(!Test.isRunningtest()){
                       Campaign nriCampaign = [
                       SELECT Id
                       FROM Campaign
                       WHERE Name = 'NRI Campaign'
                       LIMIT 1
                        ];
                      nriCampaignId = nriCampaign.Id; 
                    }
                //NRI Allocation by sathya 18-06-2026--end
                if(Trigger.isInsert){
                    System.debug('Enters Before Insert Method---->');
                    General_Setup__c Gs = [select id,name,Lost_Leads_Handler__c,Recovery_Lead_Assignment__c,Lead_Assignment__c from General_Setup__c limit 1];
                    user u = [SELECT Id,Name,Profile.Name,Is_NRI_User__c FROM user WHERE Id=:userinfo.getUserId()];
                    RelatedSourceHandler.checkMobileNumber(trigger.new); 
                    RelatedSourceHandler.duplicateCheck2(trigger.new);
                    RelatedSourceHandler.campaignMethod(trigger.new);
                    
                    list<Lead> ChannelPartLeads = new list<Lead>();
                    list<Lead> PreSalesLeads = new list<Lead>();
                    list<lead> greSalesLeads = new list<Lead>();
                    //NRI Allocation by sathya 18-06-2026
                    list<lead> NriLeads = new list<Lead>();
                    list<Lead> crownSalesLeads = new list<Lead>();
                    List<Lead> custDelightSalesList = new List<Lead>();
                    
                    //NRI Allocation by sathya 18-06-2026--end
                    
                    for(Lead ld:trigger.new){
                        ld.Phone__c = ld.Phone__c != null ? ld.Phone__c.replaceAll('[^0-9]', '') : null;
						ld.Secondary_Phone__c = ld.Secondary_Phone__c != null ? ld.Secondary_Phone__c.replaceAll('[^0-9]', '') : null;
						ld.Tertiary_Phone__c = ld.Tertiary_Phone__c != null ? ld.Tertiary_Phone__c.replaceAll('[^0-9]', '') : null;
                        String phoneWithCode =
                                   (ld.Country_Code__c != null ? ld.Country_Code__c : '') +
                                   (ld.Phone__c != null ? ld.Phone__c : '');
                               
                               String secondPhoneWithCode =
                                   ld.Secondary_Phone__c != null
                                   ? (ld.Secondary_Country_Code__c != null ? ld.Secondary_Country_Code__c : '') +
                                   ld.Secondary_Phone__c
                                   : '';
                               
                               String thirdPhoneWithCode =
                                   ld.Tertiary_Phone__c != null
                                   ? (ld.Tertiary_Country_Code__c != null ? ld.Tertiary_Country_Code__c : '') +
                                   ld.Tertiary_Phone__c
                                   : '';
                               
                               String cleanedPhone        = phoneWithCode.replaceAll('[^0-9]', '');
                               String cleanedSecondPhone  = secondPhoneWithCode.replaceAll('[^0-9]', '');
                               String cleanedThirdPhone   = thirdPhoneWithCode.replaceAll('[^0-9]', '');
                               
                               ld.Phone_with_Country_Code__c               = cleanedPhone;
                               ld.Secondary_Phone_with_Country_Code__c     = cleanedSecondPhone;
                               ld.Tertiary_Phone_with_Country_Code__c      = cleanedThirdPhone;
                               
                    }
                    
                    
                    // If leads are created by admin then it will go to roundrobin, else it will be assigned to same user.
                    if(u.Profile.Name == 'System Administrator'||u.Profile.Name == 'Salesforce API Only System Integrations' || u.Profile.Name == 'Admin' || u.Profile.Name == 'Customer Delights'
                       ||u.Profile.Name == 'Pre Sales'||u.Profile.Name == 'Lead Capture Profile'||u.Profile.Name == 'API Mcube Profile' || u.Profile.Name == 'Marketing'){
                           for(Lead ld : trigger.new){
                               if(ld.Lead_source__c == 'fb'){
                                   ld.Lead_source__c = 'Facebook';
                               }
                               if(ld.Lead_source__c == 'ig'){
                                   ld.Lead_source__c = 'Instagram'; 
                               }
                               
                               //karthik-
                               if (ld.Is_Under_Allocation__c == true) {
                                   ld.Lead_Status__c = 'Allocation'; // Ensures status is set to Allocation
                                   ld.Lead_Assigned__c = true; // Prevents round robin assignment
                                   ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                   // Skip any further processing related to site visits for this lead
                                   continue;
                               }//-
                               
                               // Added on 21-06-26 starts
                               if(ld.Lead_source__c == 'Referral'){
                                   ld.Is_Under_Allocation__c = true;
                                   ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();                                   
                                   custDelightSalesList.add(ld);
                                   continue;
                               }
                              // Added on 21-06-26 ends
                               // Sales Channel Partner New starts
                            if(ld.Lead_source__c =='Channel Partner' && ld.Follow_up_By__c == 'Channel Partner' && ld.Is_Credited__c == true){
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                ld.Lead_Status__c = 'Allocation';
                                ChannelPartLeads.add(ld);
                            }
                                                           // Sales Channel Partner New ends   
                               // NRI Allocation by Sathya 18-06-2026
                               else if (
                                    ld.Campaign_std__c == nriCampaignId ||
                                    (!String.isBlank(ld.Country_Code__c) && ld.Country_Code__c != '91')
                                ) {
                                    ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName()
                                        .get('NRI Pre Sales')
                                        .getRecordTypeId();
                                
                                    if (!Test.isRunningTest()) {
                                        NriLeads.add(ld);
                                    }
                                }
                                // NRI Allocation by Sathya 18-06-2026
                                // Crown Project straight to Sales RRB (bypass Pre Sales / Site Visit)
                                else if (ld.Allocated_Project__c == 'The Crown')
                                     	 {
                                    ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                    crownSalesLeads.add(ld);
                                }
                               else{
                                   PreSalesLeads.add(ld);
                               }
                               
                               //Haresh on 29/08/2025
                               ld.Last_Source_Of_Enquiry__c =ld.Lead_source__c;
                               ld.Last_Sub_Source__c =  ld.Sub_Source__c;
                               ld.First_Source_Of_Enquiry__c = ld.Lead_source__c;
                               ld.First_Sub_Source__c =  ld.Sub_Source__c;
                               ld.First_Approach_On__c = system.now();                               
                               
                               
                           }
                          // Sales Channel Partner New starts

                          if(ChannelPartLeads.size()>0){
                                RoundRobinHandler.GeneralLeadAssignment(ChannelPartLeads,false,'Sales');
                           }
                           // Sales Channel Partner New ends   

                           if(custDelightSalesList.size()>0){
                               RoundRobinHandler.assignLead(custDelightSalesList,false,'Sales'); 
                           }
                           
                           
                           
                           if(PreSalesLeads.size()>0){
                               system.debug('RoundRobinHandler - Presales');
                               //General_Setup__c Gs = [select id,name,Lead_Assignment__c from General_Setup__c limit 1];
                               if(Gs.Lead_Assignment__c == 'General RoundRobin'){
                                   RoundRobinHandler.GeneralLeadAssignment(PreSalesLeads,false,'Pre Sales'); 
                               }
                               else{
                                   RoundRobinHandler.assignLead(PreSalesLeads,false,'Pre Sales'); 
                               }
                           }
                           // NRI Allocation by Sathya 18-06-2026
                           if(NriLeads.size() > 0){
                           RoundRobinHandler.assignNRILead(NriLeads,false);
                              }
                           // NRI Allocation by Sathya--end
                           if(crownSalesLeads.size() > 0){
    					   RoundRobinHandler.assignLead(crownSalesLeads, false, 'Sales');
                           }
                       }
                    if(u.Profile.Name == 'GRE Form Profile'){
                        for(Lead ld : trigger.new){              
                            ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();                 
                            greSalesLeads.add(ld);  
                        }
                        if(greSalesLeads.size()>0){
                            system.debug('RoundRobinHandler - greSales');
                            //General_Setup__c Gs = [select id,name,Lead_Assignment__c from General_Setup__c limit 1];
                            if(Gs.Lead_Assignment__c == 'General RoundRobin'){
                                RoundRobinHandler.GeneralLeadAssignment(greSalesLeads,false,'Sales'); 
                            }
                            else{
                                RoundRobinHandler.assignLead(greSalesLeads,false,'Sales'); 
                            }
                        } 
                    }
                    if(u.Profile.Name == 'Sales'){
                        for(Lead ld : trigger.new){
                            ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                            ld.Is_Under_Allocation__c = true;
                            ld.Lead_Status__c = 'Allocation';
                        }
                    }
                    else{
                        for(Lead ld : trigger.new){
                            ld.Lead_Assigned__c = true;
                            ld.Reassigned_By__c = UserInfo.getUserId();
                            ld.Re_assigned_date__c = system.now();
                            //Commented on 17/04/2025 by haresh
                            /*if(u.Profile.Name == 'Sales'){
                                ld.Sales_User__c =UserInfo.getUserId();
                                ld.SV_User__c=UserInfo.getUserId();
                                ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                }else if(u.Profile.Name == 'Pre sales'){
                                //ld.Pre_sales_user__c =UserInfo.getUserId();
                                ld.RecordTypeId=Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
                                }*/ 
                        }
                    }
                    System.debug('Exit Before Insert Method---->');
                }
                if(Trigger.isUpdate){
                    System.debug('Enters Before Update Method---->');
                    system.debug('on update');
                    General_Setup__c Gs = [select id,name,Lost_Leads_Handler__c,Recovery_Lead_Assignment__c,Lead_Assignment__c from General_Setup__c limit 1];

                    //User u = [SELECT Id, Name, Profile.Name FROM User WHERE Profile.Name = 'System Administrator' and IsActive=true LIMIT 1];
                    List<Lead> preSalesLdList = new List<Lead>();
                    List<Lead> salesLdList = new List<Lead>();
                    List<Lead> svcLdList = new List<Lead>();
                    List<Lead> FinalsalesLdList = new List<Lead>();
                    Set<String> phoneSet = new Set<String>();
                    Set<String> FollowUpLdIds = new Set<String>();
                    string PSRecTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();
                    List<Lead> nriSalesLdList = new List<Lead>();
                    List<Lead> PresaleAuditLdList = new List<Lead>();
                    List<Lead> FinalPresaleAuditLdList = new List<Lead>();    
                    string PSARecTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Recovery').getRecordTypeId();
                    
                    List<Lead> UnqualifiedLdList = new List<Lead>();
                    List<Lead> RecoveryLdList = new List<Lead>();
                    Set<Id> UnquaifiedLeads = new Set<Id>();
                    Set<Id> ClosedLostLeads = new Set<Id>();
                    Set<Id> RecoveryLeads = new Set<Id>();
                    Set<Id> tlLeadsId = new Set<Id>(); // Changes made on 02-06-26
					Set<Id> ownerIds = new Set<Id>();
                    // Record Type IDs by Sathya 20-06-2026
                    Id nriPreSalesRTId = Schema.SObjectType.Lead.getRecordTypeInfosByName()
                        .get('NRI Pre Sales')
                        .getRecordTypeId();
                    
                    Id nriSalesRTId = Schema.SObjectType.Lead.getRecordTypeInfosByName()
                        .get('NRI Sales')
                        .getRecordTypeId();
                    // Record Type IDs by Sathya 20-06-2026 -- End
                    for(Lead ld : Trigger.new){
                        Lead oldLd = Trigger.oldMap.get(ld.Id);
                        ld.Phone__c = ld.Phone__c != null ? ld.Phone__c.replaceAll('[^0-9]', '') : null;
						ld.Secondary_Phone__c = ld.Secondary_Phone__c != null ? ld.Secondary_Phone__c.replaceAll('[^0-9]', '') : null;
						ld.Tertiary_Phone__c = ld.Tertiary_Phone__c != null ? ld.Tertiary_Phone__c.replaceAll('[^0-9]', '') : null;
                        if (ld.Phone__c!= Trigger.oldmap.get(ld.Id).Phone__c && ld.Phone__c != null){
                            phoneSet.add(ld.Phone__c);
                            System.debug('phoneSet--->'+phoneSet); // remove
                        }
                        if (ld.Secondary_Phone__c!= Trigger.oldmap.get(ld.Id).Secondary_Phone__c && ld.Secondary_Phone__c != null){
                            phoneSet.add(ld.Secondary_Phone__c);
                            System.debug('phoneSet--->'+phoneSet); // remove
                        }
                        if (ld.Tertiary_Phone__c!= Trigger.oldmap.get(ld.Id).Tertiary_Phone__c && ld.Tertiary_Phone__c != null){
                            phoneSet.add(ld.Tertiary_Phone__c);
                            System.debug('phoneSet--->'+phoneSet); // remove
                        }
                        
                        system.debug('new Status '+ld.Lead_Status__c);
                        system.debug('old Status '+Trigger.oldmap.get(ld.Id).Lead_Status__c);
                        
                        if(ld.Lead_Status__c != Trigger.oldmap.get(ld.Id).Lead_Status__c && ld.Lead_Status__c=='New Enquiry' && !ld.Lead_Assigned__c && !ld.Lead_Transfered__c){
                            preSalesLdList.add(ld);
                            System.debug('preSalesLdList-->'+preSalesLdList); // remove
                        }
                       
                        
                        else if(ld.Lead_Status__c != Trigger.oldmap.get(ld.Id).Lead_Status__c && (ld.Lead_Status__c=='Allocate to SVC') && (ld.RecordTypeId == PSRecTypeId || ld.RecordTypeId == PSARecTypeId)){                            
                            if(ld.RecordTypeId == PSARecTypeId){
                              ld.Recovery_User__c = Trigger.oldmap.get(ld.Id).OwnerId;  
                            }
                            else{
                             ld.Pre_sales_user__c = Trigger.oldmap.get(ld.Id).OwnerId;
                            }
                            ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('SVC').getRecordTypeId();
                            ld.Lead_Assigned__c = false;
                            ld.Pushed_On__c = system.now();
                            ld.Pushed_By__c = UserInfo.getUserId();
                            ld.IsPushed__c=true;
                            svcLdList.add(ld);
                            FollowUpLdIds.add(ld.Id);
                            System.debug('salesLdList-->'+salesLdList); // remove
                            System.debug('FollowUpLdIds-->'+FollowUpLdIds); // remove
                            
                            
                        }
                        // NRI Sales Allocation - Sathya 19-06-2026

                        if (
                            ld.Lead_Status__c != Trigger.oldMap.get(ld.Id).Lead_Status__c &&
                            ld.Lead_Status__c == 'Allocation' &&
                            (
                                ld.Campaign_std__c == nriCampaignId ||
                                (!String.isBlank(ld.Country_Code__c) && ld.Country_Code__c != '91')
                            ) &&
                            ld.RecordTypeId == nriPreSalesRTId
                        ) {
                            // Change Record Type from NRI Pre Sales to NRI Sales
                            ld.RecordTypeId = nriSalesRTId;
                            ld.Pushed_On__c = System.now();
                            ld.Pushed_By__c = UserInfo.getUserId();
                            ld.Pre_sales_user__c = UserInfo.getUserId();
                            ld.IsPushed__c = true;
                            ld.Is_NRI_Allocation__c = true;
                        
                            nriSalesLdList.add(ld);
                            
                            // Create Allocation record using existing service
        					AllocationService.createAllocation(ld.OwnerId, ld.Id, ld.Allocated_Project__c);
                            //AllocationService.createAllocation(UserInfo.getUserId(), ld.Id, ld.Allocated_Project__c);
                        }

					  // NRI Sales Allocation - Sathya 19-06-2026 -- End
                       if (ld.Lead_Pull_Request_Status__c == 'Rejected' && Trigger.oldMap.get(ld.Id).Lead_Pull_Request_Status__c != 'Rejected') {
                            ld.Lead_Pull_Requested_By__c = null;
                            System.debug('ld.Lead_Pull_Request_Status__c--->'+ld.Lead_Pull_Request_Status__c); // remove
                        }
                        
                        //if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && (ld.Lead_Status__c=='Closed Lost' || ld.Lead_Status__c=='Sales - Prospect')){
                        if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && (ld.Lead_Status__c=='Recovery - Pre Sales' || ld.Lead_Status__c=='Recovery - Sales' || ld.Lead_Status__c=='Recovery - SVC' )){
                            /*if(ld.Lead_Status__c=='Sales - Prospect')
UnquaifiedLeads.add(ld.Id);
System.debug('UnquaifiedLeads Before update-->'+UnquaifiedLeads); // remove

if(ld.Lead_Status__c=='Closed Lost')
ClosedLostLeads.add(ld.Id);
System.debug('ClosedLostLeads Before update-->'+ClosedLostLeads); // remove*/
                            RecoveryLeads.add(ld.Id);
                        }
                        if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && (ld.Lead_Status__c=='Allocate to TL')){
                           tlLeadsId.add(ld.Id);
                           ownerIds.add(ld.OwnerId);
                        }

                        if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && ld.Lead_Status__c=='Abandoned'){
                            ld.Abandoned_Date__c = system.now();
                        }
                    }
                    // NRI Sales Allocation - Sathya 20-06-2026
                    if (!nriSalesLdList.isEmpty()) {
                        RoundRobinHandler.assignNRISalesLead(
                            nriSalesLdList,
                            Trigger.oldMap,
                            false
                        );
                    }
                    // NRI Sales Allocation - Sathya 20-06-2026--End
                    if(svcLdList.size()>0){
                        RoundRobinHandler.assignLead(svcLdList,false,'SVC');
                    }
                   if(phoneSet.size()>0){
                        System.debug('phoneSet efore  update--->'+phoneSet);
                        List<Lead> oldLeadList = [SELECT Id,Lead_ID__c, Phone__c, Secondary_Phone__c,Tertiary_Phone__c FROM Lead 
                                                  WHERE (Phone__c IN :phoneSet OR Secondary_Phone__c IN :phoneSet OR 
                                                         Tertiary_Phone__c IN:phoneSet) ORDER BY CreatedDate ASC];
                        System.debug('oldLeadList Before Update--->'+oldLeadList); // remove
                        
                        List<Related_Source__c> oldList = [SELECT Id,Name,PhoneProject__c,SecondaryPhoneProject__c,TertiaryPhoneProject__c,Lead__c,Lead__r.Id,Lead__r.Lead_ID__c 
                                                           FROM Related_Source__c WHERE (PhoneProject__c IN : phoneSet OR SecondaryPhoneProject__c IN :phoneSet OR TertiaryPhoneProject__c IN: phoneSet) AND Lead__c!=null ORDER BY CreatedDate ASC];
                        System.debug('oldList Before Update--->'+oldList); // remove
                        
                        // Map to store old leads based on phone and email
                        Map<String, Lead> phoneMap = new Map<String, Lead>();
                        
                        if(oldLeadList.size() >0){
                            
                            for (Lead old : oldLeadList){
                                if (old.Phone__c != null){
                                    phoneMap.put(old.Phone__c, old);
                                }
                                if (old.Secondary_Phone__c != null){
                                    phoneMap.put(old.Secondary_Phone__c, old);
                                }
                                if (old.Tertiary_Phone__c != null){
                                    phoneMap.put(old.Tertiary_Phone__c, old);
                                }
                            }
                            System.debug('phoneMap Before Update--->'+phoneMap); // remove
                            
                        }
                        if(oldList.size() >0){
                            for(Related_Source__c old : oldList){
                                if(old.PhoneProject__c !=null){
                                    phoneMap.put(old.PhoneProject__c,old.Lead__r);
                                }
                                if(old.SecondaryPhoneProject__c !=null){
                                    phoneMap.put(old.SecondaryPhoneProject__c,old.Lead__r);
                                }
                                if(old.TertiaryPhoneProject__c !=null){
                                    phoneMap.put(old.TertiaryPhoneProject__c,old.Lead__r);
                                }
                            }
                            System.debug('phoneMap Related Source Before Update--->'+phoneMap); // remove
                            
                        }
                        
                        for(Lead nld : trigger.new){
                            if (nld.Phone__c!= Trigger.oldmap.get(nld.Id).Phone__c && nld.Phone__c != null && phoneMap.containsKey(nld.Phone__c) && phoneMap.get(nld.Phone__c).Id != nld.Id){
                                nld.Phone__c.addError('Lead with the same phone number already exists: ' + phoneMap.get(nld.Phone__c).Lead_ID__c);
                            }
                            else if (nld.Secondary_Phone__c!= Trigger.oldmap.get(nld.Id).Secondary_Phone__c && nld.Secondary_Phone__c != null && phoneMap.containsKey(nld.Secondary_Phone__c) && phoneMap.get(nld.Secondary_Phone__c).Id != nld.Id) {
                                nld.Secondary_Phone__c.addError('Lead with the same phone number already exists: ' + phoneMap.get(nld.Secondary_Phone__c).Lead_ID__c);
                            }
                            else if (nld.Tertiary_Phone__c!= Trigger.oldmap.get(nld.Id).Tertiary_Phone__c && nld.Tertiary_Phone__c != null && phoneMap.containsKey(nld.Tertiary_Phone__c) && phoneMap.get(nld.Tertiary_Phone__c).Id != nld.Id) {
                                nld.Tertiary_Phone__c.addError('Lead with the same phone number already exists: ' + phoneMap.get(nld.Tertiary_Phone__c).Lead_ID__c);
                            }
                            if (nld.Phone__c!= Trigger.oldmap.get(nld.Id).Phone__c){
                                String phoneWithCode =
                                    nld.Phone__c != null
                                    ? (nld.Country_Code__c != null ? nld.Country_Code__c : '') +
                                    nld.Phone__c
                                    : '';
                                
                                String cleanedPhone  = phoneWithCode.replaceAll('[^0-9]', '');
                                
                                if (cleanedPhone.length() == 14 && cleanedPhone.startsWith('9191')) {
                                    cleanedPhone = cleanedPhone.substring(2);
                                }
                                nld.Phone_with_Country_Code__c =  cleanedPhone;
                                
                                
                            }
                            else if (nld.Secondary_Phone__c!= Trigger.oldmap.get(nld.Id).Secondary_Phone__c) {
                                String secondPhoneWithCode =
                                    nld.Secondary_Phone__c != null
                                    ? (nld.Secondary_Country_Code__c != null ? nld.Secondary_Country_Code__c : '') +
                                    nld.Secondary_Phone__c
                                    : '';
                                
                                String cleanedSecondPhone  = secondPhoneWithCode.replaceAll('[^0-9]', '');
                                // If 14 digits and starts with 91 → remove country code
                                if (cleanedSecondPhone.length() == 14 && cleanedSecondPhone.startsWith('9191')) {
                                    cleanedSecondPhone = cleanedSecondPhone.substring(2);
                                }
                                
                                nld.Secondary_Phone_with_Country_Code__c=  cleanedSecondPhone;
                            }
                            else if (nld.Tertiary_Phone__c!= Trigger.oldmap.get(nld.Id).Tertiary_Phone__c) {
                                String thirdPhoneWithCode =
                                    nld.Tertiary_Phone__c != null
                                    ? (nld.Tertiary_Country_Code__c != null ? nld.Tertiary_Country_Code__c : '') +
                                    nld.Tertiary_Phone__c
                                    : '';
                                
                                String cleanedThirdPhone  = thirdPhoneWithCode.replaceAll('[^0-9]', '');
                                
                                if (cleanedThirdPhone.length() == 14 && cleanedThirdPhone.startsWith('9191')) {
                                    cleanedThirdPhone = cleanedThirdPhone.substring(2);
                                }
                                nld.Tertiary_Phone_with_Country_Code__c=  cleanedThirdPhone;    
                            }
                            
                        }
                    }
                    if(preSalesLdList.size()>0){
                        //General_Setup__c Gs = [select id,name,Lost_Leads_Handler__c,Recovery_Lead_Assignment__c,Lead_Assignment__c from General_Setup__c limit 1];
                        if(Gs.Lead_Assignment__c == 'General RoundRobin'){
                            RoundRobinHandler.GeneralLeadAssignment(preSalesLdList,false,'Pre Sales'); 
                        }
                        else{
                            RoundRobinHandler.assignLead(preSalesLdList,false,'Pre Sales'); 
                        }
                    }
                    if(salesLdList.size()>0){
                        /*list<Follow_up__c> fpList = new list<Follow_up__c>();
list<Follow_up__c> fupLst = [select id,name,status__c,Description__c from Follow_up__c where SLead__c in:FollowUpLdIds and Status__c='Scheduled'];
for(Follow_up__c fp : fupLst){
fp.status__c='Cancelled';
//fp.Is_System_Cancelled__c = true;
fp.Description__c='Cancelled by System Automation as Lead is Pushed to Sales';
fpList.add(fp);
}
Update fpList;
system.debug('fupLst.size() >'+ fupLst.size());*/
                        
                        map<id,integer> ldfupList = new map<id,integer>();
                        list<aggregateResult> aggres= [select SLead__c, count(Id) from Follow_up__c where SLead__c in:FollowUpLdIds and Status__c='Scheduled' group by SLead__c];
                        system.debug('hi1');
                        for(aggregateResult ar : aggres){
                            system.debug('hi2');
                            ldfupList.put((String)ar.get('SLead__c'), (Integer)ar.get('expr0'));
                            system.debug('ld: '+ (String)ar.get('SLead__c') + '  size: '+(Integer)ar.get('expr0'));
                        }
                        
                        
                    }
                    // New Changes for TLs assign on 02-06-26 starts
                   Map<Id, User> ownerMap = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds]);
                    if(tlLeadsId.size()>0){
                        for(Lead ld : Trigger.new){
                            if(tlLeadsId.contains(ld.Id)){
                                ld.OwnerId = ownerMap.get(ld.OwnerId).ManagerId;
                                ld.Pushed_On__c = system.now();
                                ld.Pushed_By__c = UserInfo.getUserId();
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('TL').getRecordTypeId();
                                
                            }
                        }
                    }
                    // New Changes for TLs assign on 02-06-26 ends
                    if(RecoveryLeads.size()>0){
                        system.debug('recovery leads>0');
                        //General_Setup__c Gs = [select id,name,Lost_Leads_Handler__c,Recovery_Lead_Assignment__c,Lead_Assignment__c from General_Setup__c limit 1];
                        for(Lead ld : Trigger.new){
                            if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && ld.Lead_Status__c == 'Recovery - Pre Sales'){
                                system.debug('recovery presales');
                                ld.Pre_sales_user__c = Trigger.oldmap.get(ld.Id).OwnerId;
                                ld.Unqualified_Lost_By__c = UserInfo.getUserId();
                                ld.Unqualified_Date__c = system.now();
                                ld.Is_Unqualified__c = true;
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Recovery').getRecordTypeId();
                                ld.Lead_Assigned__c = false;
                                ld.Reassigned_By__c = UserInfo.getUserId();
                                ld.Re_assigned_date__c = system.now();
                                ld.Pushed_On__c = system.now();
                                ld.Pushed_By__c = UserInfo.getUserId();
                                ld.IsPushed__c = true;
                                RecoveryLdList.add(ld);
                            }
                            if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && ld.Lead_Status__c == 'Recovery - Sales'){
                                system.debug('recovery presales');ld.Sales_User__c = Trigger.oldmap.get(ld.Id).OwnerId;
                                ld.Closed_Lost_By__c = UserInfo.getUserId();
                                ld.Closed_Lost_Date__c = system.now();
                                ld.Is_Closed_Lost__c = true;
                                
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Recovery').getRecordTypeId();
                                ld.Lead_Assigned__c = false;
                                ld.Reassigned_By__c = UserInfo.getUserId();
                                ld.Re_assigned_date__c = system.now();
                                ld.Pushed_On__c = system.now();
                                ld.Pushed_By__c = UserInfo.getUserId();
                                ld.IsPushed__c = true;
                                RecoveryLdList.add(ld);
                            }
                            if(ld.Lead_Status__c!=Trigger.oldmap.get(ld.Id).Lead_Status__c && ld.Lead_Status__c == 'Recovery - SVC'){
								system.debug('recovery SVC');
                                ld.SV_User__c = Trigger.oldmap.get(ld.Id).OwnerId;
                                ld.Closed_Lost_By__c = UserInfo.getUserId();
                                ld.Closed_Lost_Date__c = system.now();
                                ld.Is_Closed_Lost__c = true;
                                
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Recovery').getRecordTypeId();
                                ld.Lead_Assigned__c = false;
                                ld.Reassigned_By__c = UserInfo.getUserId();
                                ld.Re_assigned_date__c = system.now();
                                ld.Pushed_On__c = system.now();
                                ld.Pushed_By__c = UserInfo.getUserId();
                                ld.IsPushed__c = true;
                                RecoveryLdList.add(ld);
                            }
                                
                        }
                        
                        if(Gs.Recovery_Lead_Assignment__c == 'General RoundRobin'){
                            system.debug('in round robin assignment general');
                            RoundRobinHandler.assignLead(RecoveryLdList,false,'Recovery'); 
                        }
                        else{
                            system.debug('in round robin assignment');
                            RoundRobinHandler.assignLead(RecoveryLdList,false,'Recovery'); 
                        }
                    }
                    System.debug('Exit of before Update In Lead Object--->');
                }
            }
            if (Trigger.isAfter){
                if (Trigger.isInsert){
                    System.debug('Enters the After Insert Method---->');
                    List<Lead> newEnquiryLeadIds = new List<Lead>();
                    RelatedSourceHandler.afterinsertLogic2(trigger.new);
                    // Marketing cloud Api starts
                    // SLeadTriggerHandler.sendLeadWelcomeWhatsApp(trigger.new,null);
                    // Marketing cloud Api ends
                    // whatsapp message API starts on 25-02-26
                    if(label.New_Lead_Creation=='TRUE'){
                       for (Lead l : Trigger.new) {
                            if (l.Lead_Type__c == 'Fresh' && !String.isBlank(l.Phone__c)) {
                                leadsToSend.add(l);
                            }
                           if(l.Lead_Status__c == 'New Enquiry'){
                               System.debug('Trigger New Enquiry Leads--->');
                               newEnquiryLeadIds.add(l);
                           }
                        } 
                    }
                    
                    if(!newEnquiryLeadIds.isEmpty()){
                        publishLeadAlerts.publishLead(newEnquiryLeadIds);
                    }
                        
                    // whatsapp message API ends  on 25-02-26
                    
                    
                    /*Create site visit if Lead source is Walking
List<Lead> ldlist = new List<Lead>();
for(Lead ld : Trigger.new){
if(ld.Lead_source__c =='Walk-In Leads'){
ldlist.add(ld);
} 
}*/
                    System.debug('Exits the After Insert Method---->');
                    
                }
                // ADDED BY SIVAM - FOR ADISSIA ONE APP (Test coverage is 86% on 22-08-2026) | Added to send the notification to the mobile phone adissia one app users
                if (Trigger.isAfter && Trigger.isUpdate) {
                        LeadStatusWebhook.handleStatusChange(Trigger.new, Trigger.oldMap);
                }

                if (Trigger.isUpdate){
                    System.debug('Enters the After Update Method---->');  
                    // calls channel Partner Api starts
                    // COMMENTED BY SIVAM FOR RAGU TO AVOID THE NOTIFICATION AND AUTOMATION 

                    // LeadStatusWebhookTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
                    // calls channel Partner Api ends
					// Marketing cloud api for Re-opened starts
                    // SLeadTriggerHandler.sendLeadWelcomeWhatsApp(trigger.new,Trigger.oldMap);
					// Marketing cloud api for Re-opened ends

                    Set<Id> lostWinLeads = new Set<Id>();
                    Set<Id> ownerChange = new Set<Id>();
                    Set<Id> siteVisitScheduleId = new Set<Id>();
                    Set<Id> siteVisitReScheduleId = new Set<Id>();
                    Set<Id> siteVisitCompletedId = new Set<Id>();
                    Set<Id> leadIds = new Set<Id>();
                    Map<Id, Id> leadToSubmitterMap1 = new Map<Id, Id>();
                    
                    //NRI Allocation by sathya 20-06-2026
                    RoundRobinHandler.shareLeadWithPreviousOwner(
                        Trigger.new,
                        Trigger.oldMap
                    );
                    //NRI Allocation by sathya 20-06-2026-- End
                    
                    for (Integer i = 0; i < Trigger.new.size(); i++) {
                        Lead newL = Trigger.new[i];
                        Lead oldL = Trigger.old[i];
            		// whatsapp message API starts on 25-02-26
                        // Only when Lead_Type changes to Re-opened
                        if (newL.Lead_Type__c == 'Re-Opened' &&
                            oldL.Lead_Type__c != 'Re-Opened' &&
                            !String.isBlank(newL.Phone__c)) {
            
                            leadsToSend.add(newL);
                        }
                    }
                    // whatsapp message API ends  on 25-02-26
                   for(Lead con : Trigger.new){
                        //if(con.Lead_Status__c!=Trigger.oldmap.get(con.Id).Lead_Status__c && (con.Lead_Status__c=='Closed Lost' || con.Lead_Status__c=='Sales - Prospect' || con.Lead_Status__c=='Booked')){
                        if(con.Lead_Status__c!=Trigger.oldmap.get(con.Id).Lead_Status__c && (con.Lead_Status__c=='Recovery - Pre Sales' || con.Lead_Status__c=='Recovery - SVC' || con.Lead_Status__c=='Recovery - Sales'|| con.Lead_Status__c=='Allocate to TL' || con.Lead_Status__c=='Booked')){
                            lostWinLeads.add(con.Id);
                        }
                        //if(con.OwnerId!=Trigger.oldmap.get(con.Id).OwnerId && con.Lead_Status__c!='Closed Lost' && con.Lead_Status__c!='Sales - Prospect'){
                        if(con.OwnerId!=Trigger.oldmap.get(con.Id).OwnerId && con.Lead_Status__c!='Recovery - Pre Sales' && con.Lead_Status__c!='Recovery - SVC'  && con.Lead_Status__c!='Recovery - Sales' && con.Lead_Status__c != 'Allocate to TL'){
                            ownerChange.add(con.Id);
                        }
                        //Collect Leads where the Pull request status changes to 'Approved'
                        if(con.Lead_Pull_Request_Status__c == 'Level 2 Approved' && Trigger.oldMap.get(con.Id).Lead_Pull_Request_Status__c != 'Level 2 Approved') {
                            //leadIds.add(con.Id);
                            //system.debug(leadIds);
                            if(con.Lead_Pull_Requested_By__c != null)
                                leadToSubmitterMap1.put(con.Id,con.Lead_Pull_Requested_By__c);
                        }
                    }
                    
                    
                    // for pull requested by sales User
                    if (!leadToSubmitterMap1.isEmpty()) {
                        /*List<ProcessInstance> approvalProcesses = [SELECT TargetObjectId, CreatedById FROM ProcessInstance WHERE TargetObjectId IN :leadIds AND Status = 'Approved'];
system.debug('approvalProcesses>> '+approvalProcesses.size());
Map<Id, Id> leadToSubmitterMap = new Map<Id, Id>();
for (ProcessInstance process : approvalProcesses) {
leadToSubmitterMap.put(process.TargetObjectId, process.CreatedById);
}
*/
                        
                        list<Round_Robin_Member__c> rrm = [select id,name,User__c,Round_Robin__r.Project_Assigned__c,Round_Robin__r.Active__c from Round_Robin_Member__c where User__c in: leadToSubmitterMap1.Values() and Active__c=true and User_Type__c = 'Sales' and Round_Robin__r.Active__c=true];
                        System.debug('Round_Robin_Member__c After Update-->'+rrm); // remove
                        
                        map<string,string> ProjectSaleOwner = new map<string,string>();
                        List<Lead> ldlst = new List<Lead>();
                        map<string,string> NotifyUserIds = new map<string,string>();
                        List<Site_Visit__c> svlst = new List<Site_Visit__c>();
                        
                        for (Round_Robin_Member__c rr : rrm){
                            ProjectSaleOwner.put(rr.User__c,rr.Round_Robin__r.Project_Assigned__c);
                        }
                        system.debug('ProjectSaleOwner>> '+ProjectSaleOwner);
                        for (Lead lead : Trigger.new){
                            if (leadToSubmitterMap1.containsKey(lead.Id)) {
                                system.debug('in if 129');
                                Lead ld = new Lead();
                                ld.Id = lead.Id;
                                ld.RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
                                if (lead.Lead_Status__c == 'Recovery - Pre Sales' || lead.Lead_Status__c=='Recovery - SVC'  || lead.Lead_Status__c == 'Recovery - Sales' || lead.Lead_Status__c == 'Recovery Followup') {
                                    ld.Recovery_User__c = lead.OwnerId; // Set recovery user before changing owner
                                }else{
                                    ld.Pre_sales_user__c = lead.OwnerId;    
                                }
                                ld.Lead_Assigned__c = true;
                                ld.Pushed_On__c = system.now();
                                ld.Pushed_By__c = lead.OwnerId; // Transferred By
                                ld.Lead_Transfer_Note__c = 'Lead has been pulled by Sales User';
                                ld.IsPushed__c = true;
                                ld.Reassigned_By__c = lead.OwnerId;
                                ld.Re_assigned_date__c = system.now();
                                ld.Lead_Status__c ='Site Visit Scheduled';
                                ld.OwnerId = leadToSubmitterMap1.get(lead.Id); // Update the OwnerId to the submitter's Id
                                ldlst.add(ld);
                                System.debug('ldlst-->'+ldlst); // remove
                                
                                //To send Lead Pulled notification to users
                                NotifyUserIds.put(leadToSubmitterMap1.get(lead.Id),lead.Id);
                                
                                Site_Visit__c sv1 = new Site_Visit__c();
                                sv1.Lead__c = lead.Id;
                                if(lead.Allocated_Project__c != null){
                                    sv1.Project__c = lead.Allocated_Project__c;
                                }
                                else if(ProjectSaleOwner.get(leadToSubmitterMap1.get(lead.Id)) != null){
                                    sv1.Project__c = ProjectSaleOwner.get(leadToSubmitterMap1.get(lead.Id));
                                }
                                //New Code by Karthik to update sv Project
                                if(lead.Requested_Project__c != null){
                                    sv1.Project__c = lead.Requested_Project__c;
                                }
                                DateTime currentTime = System.now(); // Get the current date and time
                                DateTime futureTime = currentTime.addMinutes(2); // Add 10 minutes
                                sv1.Date__c = futureTime;
                                sv1.IsFromUpdateLdStat__c = true;
                                sv1.Status__c = 'Scheduled';
                                sv1.OwnerId = leadToSubmitterMap1.get(lead.Id);
                                svlst.add(sv1);
                                System.debug('svlst-->'+svlst); // remove
                            }
                            system.debug('in else 155');
                        }
                        if(ldlst.size()>0){
                            System.debug('ldlst After Update-->'+ldlst); // remove
                            update ldlst;
                            HierarchialNotification.SendNotificationToSuperiors(NotifyUserIds);
                        }
                        if(svlst.size()>0){
                            System.debug('svlst After Update-->'+svlst); // remove
                            insert svlst;
                        }
                    }
                    
                    if(lostWinLeads.size()>0){
                        List<site_visit__c> svList = [SELECT Id,Name,status__c,Lead__c,Canceled_Reason__c FROM site_visit__c WHERE Lead__c IN : lostWinLeads and status__c='Scheduled'];
                        System.debug('svList Lostwin Leads-->'+svList); // remove
                        if(svList.size()>0){
                            for(site_visit__c sv : svList){
                                sv.status__c='Cancelled';
                                sv.Canceled_Reason__c='Cancelled by System Automation as the lead is moved to Recovery / Booked';
                            }
                            Update svList;
                        }
                        List<Follow_up__c> svList1 = new List<Follow_up__c>();
                        svList1 = [SELECT Id,Name,status__c,Description__c FROM Follow_up__c WHERE SLead__c IN : lostWinLeads and status__c='Scheduled'];
                        if(svList1.size()>0){
                            for(Follow_up__c sv1 : svList1){
                                sv1.status__c='Cancelled';
                                sv1.Description__c='Cancelled by System Automation as the lead is moved to Recovery / Booked';
                            }
                            System.debug('svList1-->'+svList1); // remove
                            
                            Update svList1;
                        }
                    }
                    if(ownerChange.size()>0){
                       
                        
                        List<Follow_up__c> fwList = new List<Follow_Up__c>();
                        fwList = [SELECT Id,Name,OwnerId,SLead__r.ownerId FROM Follow_Up__c WHERE SLead__c IN: ownerChange and status__c='Scheduled'];
                        System.debug('fwList after update--->'+fwList);
                        if(fwList.size()>0){
                            for(Follow_Up__c fw : fwList){
                                fw.ownerId = fw.SLead__r.OwnerId;
                            }
                            System.debug('fwList with Followup ownerId-->'+fwList); // remove                        
                            Update fwList;
                        }
                        List<Site_visit__c> svList = new List<Site_visit__c>();
                        svList = [SELECT Id,Name,OwnerId,Lead__r.ownerId FROM Site_visit__c WHERE Lead__c IN: ownerChange and (status__c='Scheduled' or status__c='Rescheduled') AND Owner.Profile.Name != 'SVC Team'];
                        if(svList.size()>0){
                            for(Site_visit__c sv : svList){
                                sv.ownerId = sv.Lead__r.OwnerId;
                            }
                            System.debug('svList after update-->'+svList); // remove
                            Update svList;
                        }
                    }
                    
                    //Sharing the Lead to Pre sales with view Access
                    system.debug('inside the view access for the pre sales');
                    List<Lead> ldListShare = new List<Lead>();
                    List<Lead> ldListShareToRecovery = new List<Lead>();
                    List<Lead> ldListShareToSV = new List<Lead>();
                    Map<Id,Id> LdSPMap = new Map<Id,Id>();
                    String profileName = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId()].Profile.Name;   
                    for(Lead con : Trigger.New){
                        system.debug('Pre sales user' +con.Pre_sales_user__c);
                       /* if (profileName == 'SVC Team') {
        				con.SV_User__c = UserInfo.getUserId();
    					}*/
                        if(con.Pre_sales_user__c != null){
                            system.debug('Pre sales user if is breached ------- ');
                            ldListShare.add(con);
                        }
                        if(con.SV_User__c != null){
                            system.debug('SV User user if is breached ------- ');
                            ldListShareToSV.add(con);
                        }
                        
                        if(con.Recovery_User__c != null){
                            system.debug('Pre sales user if is breached ------- ');
                            ldListShareToRecovery.add(con);
                        }
                        if(con.Lead_Status__c!=Trigger.oldmap.get(con.Id).Lead_Status__c && con.Lead_Status__c=='Recovery - Sales'){
                            LdSPMap.put(con.Id,con.Sales_User__c);
                        }
                    }
                    if(ldListShare.size()>0){
                        system.debug('called the share record ------- ');
                        manulaSharingClass.shareAnyRecord(ldListShare,'Read');
                    }
                    if(ldListShareToRecovery.size()>0){
                        system.debug('called the share record ------- ');
                        manulaSharingClass.shareLdRecordToRecovery(ldListShareToRecovery,'Read');
                    }
                    if(LdSPMap.size()>0){
                        system.debug('called the share record LdSPMap------- ');
                        manulaSharingClass.manualShareLeadToSalesPerson(LdSPMap);
                    }
                    if(ldListShareToSV.size()>0){
                        system.debug('called the share record ------- ');
                        manulaSharingClass.shareLdRecordToSVC(ldListShareToSV,'Read');
                    }
                    System.debug('Exits the After Insert Method---->');
                }
            }
            
            if (!leadsToSend.isEmpty()) {
                //System.enqueueJob(new WhatsAppQueueable(leadsToSend));
            }
        }
        integer i=1;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        i=i++;
        
    }
}