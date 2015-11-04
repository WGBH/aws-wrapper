require_relative 'base_wrapper'
require 'resolv'

module DnsWrapper
  include BaseWrapper
  
  private
  
  def dns_client
    @dns_client ||= Aws::Route53::Client.new(CLIENT_CONFIG)
  end
  
  public
  
  def lookup_dns(domain_name)
    aws_ip = lookup_dns_a_record(ZONE_ID, domain_name)
    dns_ip = Resolv.getaddress(domain_name)
    fail("Discrepancy for #{domain_name}: AWS=#{aws_ip} but DNS=#{dns_ip}") unless dns_ip == aws_ip
    dns_ip
  end
  
  def update_dns_a_record(zone_id, domain_name, new_ip)
    update_response = request_update_dns_a_record(zone_id, domain_name, new_ip)
    
    1.upto(WAIT_ATTEMPTS) do |try|
      break if update_insync?(update_response)
      fail('Giving up') if try >= WAIT_ATTEMPTS
      LOGGER.info("try #{try}: DNS update not yet propagated to AWS nameservers...")
      sleep(WAIT_INTERVAL)
    end
    
    1.upto(WAIT_ATTEMPTS) do |try|
      break if Resolv.getaddress(domain_name) == new_ip
      fail('Giving up') if try >= WAIT_ATTEMPTS
      LOGGER.info("try #{try}: DNS update not yet propagated to local nameserver...")
      sleep(WAIT_INTERVAL)
    end
  end
  
  def update_insync?(update_request_response)
    response = dns_client.get_change({
      id: update_request_response.change_info.id
    })
    response.change_info.status == 'INSYNC'
    # This means all the AWS NSs are up-to-date: 
    # It does not imply that DNS records have
    # been refreshed in all local caches.
  end
  
  def lookup_dns_a_record(zone_id, domain_name)
    response = dns_client.list_resource_record_sets({
      hosted_zone_id: zone_id, # required
      start_record_name: domain_name, # NOT a filter: all are returned, unless max_items set.
      start_record_type: 'A', # accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
      # start_record_identifier: "ResourceRecordSetIdentifier",
      max_items: 1,
    })
    record_sets = response.resource_record_sets
    fail("Expected 1 record set, not #{record_sets.count}") unless record_sets.count == 1
    resource_records = record_sets[0].resource_records
    fail("Expected 1 resource record, not #{resource_records.count}") unless resource_records.count == 1
    resource_records[0].value
  end
  
  def request_update_dns_a_record(zone_id, domain_name, new_ip)
    if lookup_dns_a_record(zone_id, domain_name) == new_ip
      fail("AWS says #{domain_name} already has IP #{new_ip}")
    end
    if Resolv.getaddress(domain_name) == new_ip
      fail("DNS says #{domain_name} already has IP #{new_ip}")
    end
    dns_client.change_resource_record_sets({
      hosted_zone_id: zone_id, # required
      change_batch: { # required
        # comment: "ResourceDescription",
        changes: [ # required
          {
            action: "UPSERT", # required, accepts CREATE, DELETE, UPSERT
            resource_record_set: { # required
              name: domain_name, # required
              type: "A", # required, accepts SOA, A, TXT, NS, CNAME, MX, PTR, SRV, SPF, AAAA
#              set_identifier: "ResourceRecordSetIdentifier",
#              weight: 1,
#              region: "us-east-1", # accepts us-east-1, us-west-1, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, sa-east-1, cn-north-1
#              geo_location: {
#                continent_code: "GeoLocationContinentCode",
#                country_code: "GeoLocationCountryCode",
#                subdivision_code: "GeoLocationSubdivisionCode",
#              },
#              failover: "PRIMARY", # accepts PRIMARY, SECONDARY
              ttl: 30, # required (but not documented as such)
              resource_records: [
                {
                  value: new_ip, # required
                }
              ],
#              alias_target: {
#                hosted_zone_id: "ResourceId", # required
#                dns_name: "DNSName", # required
#                evaluate_target_health: true, # required
#              },
#              health_check_id: "HealthCheckId",
            },
          },
        ],
      },
    })
  end
  
end
