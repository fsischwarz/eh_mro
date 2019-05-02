--Change DB For your environment
USE [YourDb]
GO


/*
	send_eh_mro_failure_notification looks for EH Mro failures do to customers not been setup then emails the needed parties.
*/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
GO
--Replace xxx with your preferred prefix
create   procedure [dbo].[xxx_send_eh_mro_customer_failure_notification]
as

--Script level variables

declare @searchTime int = -4
declare @rows_email int;
declare @start_date datetime = dateadd(hour,@searchTime,getdate())


--First check to make sure there are new failures to send
with xmlnamespaces('urn:com:endress:epicor:repintegration' as ns1)
select @rows_email = count(1)
from eh_mro_api_log
left outer join ship_to_ud on 
cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/PartnerNumber)[1]','nvarchar(max)') as varchar(max)) = ship_to_ud.eh_shipto_id
where status like 'failed'
			and eh_mro_api_log.type like 'create'
			and eh_mro_api_log.consumer_info like '%customer % has not been set up%'
			and eh_mro_api_log.date_created between @start_date and getdate()
			and (ship_to_ud.eh_shipto_id is null)

select @rows_email

if(@rows_email > 1)
	begin

		--email structure vars
		declare @subject varchar(255);
		declare @body varchar(max);
		declare @recipients varchar(255) = 'recipient@yourdomain.com'

		/*
			CC and BCC If you need them
			Uncomment copy_recipients and/or blind_copy_recipients
			in send db mail below
		*/
		--declare @cc varchar(255) = 'ccrecip@yourdomain.com'
		--declare @bcc varchar(255) = 'bccrecip@yourdomain.com'

		--Style sheet for html table
		declare @style varchar(max) =
			'<style type="text/css">
				table.border {border-collapse:collapse; border-spacing:0; border-color: #aaa;}
				table.border td,table.border th {padding: 5px; border-style: solid; border-width: 1px; border-color: black;}
				th {background-color: #ffff99}
				strong {font-weight: bold; color: #ff0a0a}
			</style>';
		
		--email content variables
		declare @eh_order_no varchar(40);
		declare @eh_partner_no varchar(20);
		declare @name1 varchar(255);
		declare @street varchar(255);
		declare @city varchar(255);
		declare @state varchar(10);
		declare @postalCode varchar(20);
		declare @sales_rep_first varchar(255);
		declare @sales_rep_last varchar(255);
		declare @2nd_sales_rep_first varchar(255);
		declare @2nd_sales_rep_last varchar(255);
		declare @customer_po varchar(255);
		declare @count int = 0

		--cursor for customer informtion that failed
		declare eh_mro_cur cursor for
			with xmlnamespaces('urn:com:endress:epicor:repintegration' as ns1)
			select distinct
			eh_mro_api_log.eh_order_no
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/PartnerNumber)[1]','nvarchar(max)') as varchar(20)) as [eh_partner_number]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/Name1)[1]','nvarchar(max)') as varchar(255)) as [name1]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/Street)[1]','nvarchar(max)') as varchar(255)) as [street]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/City)[1]','nvarchar(max)') as varchar(255)) as [city]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/State)[1]','nvarchar(max)') as varchar(10)) [state]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/PostalCode)[1]','nvarchar(max)') as varchar(20))as [PostalCode]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SalesRep1/FirstName)[1]','nvarchar(max)') as varchar(255)) as [sales_rep_first]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SalesRep1/LastName)[1]','nvarchar(max)') as varchar(255)) as [sales_rep_last]
			,cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/CustomerPurchaseOrder)[1]','nvarchar(max)') as varchar(255))as [customer_po]
			from eh_mro_api_log
			left outer join ship_to_ud on 
			cast(cast (request_xml as xml).value('(ns1:MT_RepDocumentData/SoldToParty/PartnerNumber)[1]','nvarchar(max)') as varchar(20)) = ship_to_ud.eh_shipto_id

			where status like 'failed'
			and eh_mro_api_log.type like 'create'
			and eh_mro_api_log.consumer_info like '%customer % has not been set up%'
			and eh_mro_api_log.date_created between @start_date and getdate()
			and (ship_to_ud.eh_shipto_id is null)

		open eh_mro_cur
		fetch next from eh_mro_cur into
			@eh_order_no,
			@eh_partner_no,
			@name1 ,
			@street ,
			@city ,
			@state ,
			@postalCode ,
			@sales_rep_first ,
			@sales_rep_last , 
			@customer_po
			while(@@FETCH_STATUS = 0)
			begin
				set @subject = 'E+H Order No: ' + @eh_order_no + ' failed for customer: ' + @eh_partner_no + ' not set up'

				set @count = @count + 1

				set @body = @style + 
							'<table>'
							+ '<tr><td colspan="3">E+H customer <strong>' + @eh_partner_no + '</strong> has not been set up in Prophet 21</td></tr>'
							+ '<tr><td> </td><td><table class="border">'
							+ '<tr><th colspan="2">SoldTo Party</th></tr>' 
							+  '<tr><td >Customer Name</td><td >'+ @name1 + '</td></tr>'
							+  '<tr><td >Address</td><td >'+ @street + '</td></tr>'
							+  '<tr><td >City</td><td >'+ @city + '</td></tr>'
							+  '<tr><td >State</td><td >'+ @state + '</td></tr>'
							+  '<tr><td >Zip</td><td >'+ @postalCode + '</td></tr>'
							+  '<tr><td >SalesRep: </td><td >' + @sales_rep_first + ' ' + @sales_rep_last + '</td></tr>'
							+  '<tr><td >Customer PO: </td><td >' + @customer_po + '</td></tr>'
							+ '</table> </td><td> </td>'
							+'</table>'

							/*Debug printing*/
							--print @count 
							--print 'loop'
							--print '*******************************'
						
						exec msdb.dbo.sp_send_dbmail
						@recipients = @recipients,
						@subject = @subject,
						@body = @body,
						@body_format = 'HTML',
						/*Change me!*/
						@profile_name = 'YourMailProfile'
						--uncomment if you need cc bcc
						/*,@copy_recipients = @cc,
						@bline_copy_recipients = @bcc*/

				fetch next from eh_mro_cur into
				@eh_order_no,
				@eh_partner_no,
				@name1 ,
				@street ,
				@city ,
				@state ,
				@postalCode ,
				@sales_rep_first ,
				@sales_rep_last ,
				@customer_po		
			end
			--cursor clean-up
			close eh_mro_cur
		deallocate eh_mro_cur

	end

GO


