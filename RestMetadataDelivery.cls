<?xml version="1.0" encoding="UTF-8"?>
<Export generator="Cache" version="25" zv="Cache for Windows (x86-64) 2018.1.2 (Build 309U)" ts="2020-06-25 21:07:49">
<Class name="OCC.Hosts.Operation.RestMetadataDelivery">
<IncludeCode>UDMFramework,%zUDMGeneralErrors</IncludeCode>
<Super>OCIELib.Operation.ODXC.InvokePESService</Super>
<TimeChanged>65335,62531.900904</TimeChanged>
<TimeCreated>65188,53555</TimeCreated>

<Parameter name="ADAPTER">
<Description><![CDATA[
<!--
Change Log
DATE	   |  DEVELOPER      |   DE/US	  |   DESCRIPTION
12/14/2018 | Franklin/Ting   | US495083   |   Created Rest operation to send the JSON request to OCC Azure Endpoint
06/14/2019 | Ayush Saxena    | US535183   | Added ability to add JWT token to request to OCC in request authorization header.
06/14/2019 | Dhanapal Ramar  | US535183   | Removed client id and client sceret initial expressoin
09/17/2019 | Ankur Awasthi	 | US535170	  | Replaced trace with logerror and added conditions for alerting on error
-->
]]></Description>
<Type>%String</Type>
<Default>EnsLib.HTTP.OutboundAdapter</Default>
</Parameter>

<Property name="Adapter">
<Type>EnsLib.HTTP.OutboundAdapter</Type>
</Property>

<Property name="oAuthClientId">
<Type>%String</Type>
<Parameter name="MAXLEN"/>
</Property>

<Property name="oAuthClientSecret">
<Type>%String</Type>
<Parameter name="MAXLEN"/>
</Property>

<XData name="MessageMap">
<Data><![CDATA[
<MapItems>
 
  <MapItem MessageType="Ens.StreamContainer">
    <Method>SendOCCStream</Method>
  </MapItem>
</MapItems>
]]></Data>
</XData>

<Method name="SendOCCStream">
<FormalSpec>pRequest:Ens.StreamContainer,*pResponse:%RegisteredObject</FormalSpec>
<ReturnType>%Status</ReturnType>
<Implementation><![CDATA[
    set tSC = $$$OK
    
	// Get metadata context for this request
	set tMetadataContext = ..GetMetadataContext()
	$$$TRACE("tMetadataContext : "_tMetadataContext)
	if tMetadataContext = "" 
	{
		quit $$$ERROR($$$ODXNoMetadataContextFound($$$CODE,""),pRequest.%Id())
	}
	
    set submissionId=$$$SUBMISSIONIDFROMCONTEXT(tMetadataContext)
    set messageId=$$$MESSAGEIDFROMCONTEXT(tMetadataContext)
    set batchId=$$$BATCHIDFROMCONTEXT(tMetadataContext)
    
    $$$TRACE("submissionId:"_submissionId_", messageId: "_messageId_", batchId: "_batchId)
    
    set oSubmission=##class(Data.Metadata.Submission).%OpenId(submissionId)
	set oMessage=##class(Data.Metadata.Message).%OpenId(messageId)
	
    try 
    {
	    set tSC=..GetJWTToken(.token)
	    $$$ThrowOnError(tSC)
		set oHttpRequest=##class(%Net.HttpRequest).%New()
		set tSC = ..CreateOCCRequest(.oHttpRequest,pRequest)
		$$$TRACE(oHttpRequest.EntityBody.Read())
		$$$ThrowOnError(tSC)
        set completeURL = ..Adapter.HTTPServer_"/"_..Adapter.URL
        $$$TRACE("Complete URL : "_completeURL) 
	    
		set oHttpRequest.Server=..Adapter.HTTPServer
		set oHttpRequest.Port=..Adapter.HTTPPort
		set oHttpRequest.SSLConfiguration=..Adapter.SSLConfig
		set oHttpRequest.SSLCheckServerIdentity=..Adapter.SSLCheckServerIdentity
		set oHttpRequest.Https=(""'=..Adapter.SSLConfig)
		set oHttpRequest.ProxyServer=..Adapter.ProxyServer,oHttpRequest.ProxyPort=..Adapter.ProxyPort
		set oHttpRequest.ProxyHTTPS=..Adapter.ProxyHTTPS
		set oHttpRequest.OpenTimeout=$select(..Adapter.ConnectTimeout=-1:2123456789,1:..Adapter.ConnectTimeout)
		set oHttpRequest.Timeout=$select(..Adapter.ResponseTimeout=-1:2123456789,1:..Adapter.ResponseTimeout)
		set oHttpRequest.ContentType="application/json"
		if ..Adapter.Credentials'=""
		{
			$$$TRACE("CredentialName : "_..Adapter.Credentials)
			set oCredential=##class(Ens.Config.Credentials).%OpenId(..Adapter.Credentials)
			if $isobject(oCredential)
			{
				$$$TRACE("UserName : "_oCredential.Username)
				set oHttpRequest.Username=oCredential.Username
				set oHttpRequest.Password=oCredential.Password
			}
		}
		Set tSC = oHttpRequest.SetHeader("Authorization","Bearer "_token)
		$$$ThrowOnError(tSC)
 		set tSC=oHttpRequest.Post(completeURL,0) 
     	$$$ThrowOnError(tSC)
 		set jsonText=""
 		set tResponse=oHttpRequest.HttpResponse     		
        if $isobject(tResponse)
        {      
        	$$$TRACE("Response Status Line : "_tResponse.StatusLine)      
        	$$$TRACE("HTTP Status Code: "_tResponse.StatusCode)
        	set jsonText=tResponse.Data.Read()
        	$$$TRACE("HTTP Response Data: "_jsonText)
        }
        
        set subStatus=oSubmission.SubmissionStatus
		set eventType=$$$ODXINFO
		set subEventText=$$$ODXRestDeliverSuccess($$$TEXT)

		if (tSC'=$$$OK)
		{
			$$$TRACE("Error :"_$System.Status.GetErrorText(tSC))
			set subEventText=$$$ODXRestDeliverFail($$$TEXT,$System.Status.GetOneErrorText(tSC))
		}
		elseif (tSC=$$$OK)&&(jsonText'["SUCCESS")
		{
			
			$$$TRACE("Failure: "_jsonText)
			set subEventText=$$$ODXRestDeliverFail($$$TEXT,jsonText)
		}
		set processingCompleteTime=##class(%Library.UTC).NowLocal()
		set tSCUpdate=$$$UPDATESUBMISSION(submissionId,processingCompleteTime,subStatus)
		set tSCAddSubEvent=$$$LOGSUBMISSIONEVENT(0, subEventText, "Custom", eventType, .pSubEventId, submissionId)   

    }
    catch Ex
    {        
        set tSC = Ex.AsStatus()
        $$$TRACE($System.Status.GetErrorText(tSC))
        set tErrorText = $System.Status.GetErrorText(tSC)
        do $$$LOGSUBMISSIONEVENT($$$FATAL,tErrorText,"Custom","Error",.pSubmissionEventId,submissionId)
        do $$$UPDATESUBMISSION(submissionId,##class(%Library.UTC).NowLocal(),"Rejected")
    }
    
    quit tSC
]]></Implementation>
</Method>

<Method name="GetMetadataContext">
<ReturnType>%String</ReturnType>
<Implementation><![CDATA[
    set tMetaDataContext = "" 
    set oMessageHeader = ##class(Ens.MessageHeader).%OpenId($$$JobCurrentHeaderId)
    
    // If metadata context was provided with the message header then use it
    // Otherwise attempt to use the session ID
    if (oMessageHeader.Description = "") {
        
        $$$TRACE($$$ODXContextFromSession($$$TEXT))
        set tMetaDataContext = $$$FULLCONTEXTFROMSESSION
    }
    else {
        
        $$$TRACE($$$ODXContextFromMsgDescription($$$TEXT))
        set tMetaDataContext = oMessageHeader.Description
        if (tMetaDataContext [ "Resent")  //handle resent messages too in case of failure
        {
        	set tMetaDataContext = $ZSTRIP($P(tMetaDataContext,":",2),"<>W")
        }
        else
        {
        	set tMetaDataContext = oMessageHeader.Description
        }
    }

    quit tMetaDataContext
]]></Implementation>
</Method>

<Method name="CreateOCCRequest">
<Description>
Method to create json request</Description>
<ClassMethod>1</ClassMethod>
<FormalSpec><![CDATA[&pHttpRequest:%Net.HttpRequest,pRequestContent:Ens.StreamContainer]]></FormalSpec>
<ReturnType>%Status</ReturnType>
<Implementation><![CDATA[
	set tSC = $$$OK
	set obj = ##class(%DynamicObject).%FromJSON(pRequestContent.Stream)
    $$$TRACE(obj.%ToJSON())
	set tSC = pHttpRequest.EntityBody.Write(obj.%ToJSON())
	if $$$ISERR(tSC) $$$LOGERROR("Cannot write data to request body : "_$System.Status.GetOneStatusText(tSC))
	quit tSC
]]></Implementation>
</Method>
</Class>
</Export>
