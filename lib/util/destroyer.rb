require_relative 'aws_wrapper'
require_relative 'lister'

# rubocop:disable Style/RescueModifier
class Destroyer < AwsWrapper
  def destroy(zone_id, name, unsafe=false)
    # We want to do as much cleaning as possible, hence the "rescue"s.

    if unsafe
      unsafe_destroy(zone_id, name)
    else
      safe_destroy(zone_id, name)
    end
  end

  private

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
  def safe_destroy(zone_id, name)
    # More conservative: Create a list of related resources to delete.
    # The downside is that if a root resource has already been deleted,
    # (like a DNS record) we won't find the formerly dependent records.

    flat_list = Lister.new(debug: @debug, availability_zone: @availability_zone)
                .list(zone_id, name, true)

    flat_list[:groups].each do |group_name|
      delete_group_policy(group_name) rescue LOGGER.warn("Error deleting policy: #{$!} at #{$@}")
      LOGGER.info("Deleted policy #{group_name}")
      delete_group(group_name) rescue LOGGER.warn("Error deleting group: #{$!} at #{$@}")
      LOGGER.info("Deleted group #{group_name}")
    end
    flat_list.delete(:groups)

    flat_list[:key_names].each do |key_name|
      delete_key(key_name) rescue LOGGER.warn("Error deleting PK: #{$!} at #{$@}")
      LOGGER.info("Deleted PK #{key_name}")
    end
    flat_list.delete(:key_names)

    flat_list[:snapshot_ids].each do |snapshot_id|
      delete_snapshot(snapshot_id) rescue LOGGER.warn("Error deleting snapshot: #{$!} at #{$@}")
      LOGGER.info("Deleted snapshot #{snapshot_id}")
    end
    flat_list.delete(:snapshot_ids)

    flat_list[:elb_names].each do |elb_name|
      delete_elb(elb_name) rescue LOGGER.warn("Error deleting ELB: #{$!} at #{$@}")
      LOGGER.info("Deleted ELB #{elb_name}")
    end
    flat_list.delete(:elb_names)

    terminate_instances_by_id(flat_list[:instance_ids]) rescue LOGGER.warn("Error terminating EC2 instances: #{$!} at #{$@}")
    LOGGER.info("Terminated EC2 instances #{flat_list[:instance_ids]}")
    flat_list.delete(:instance_ids)
    flat_list.delete(:volume_ids) # Volumes are set to disappear with their instance.

    delete_dns_cname_records(zone_id, flat_list[:cnames]) rescue LOGGER.warn("Error deleting CNAMEs: #{$!} at #{$@}")
    LOGGER.info("Deleted CNAMEs #{flat_list[:cnames]}")
    flat_list.delete(:cnames)

    flat_list.keys.tap do |forgot|
      fail("Still need to clean up #{forgot}") unless forgot.empty?
    end
  end

  def unsafe_destroy(zone_id, name)
    # Delete resources based on name conventions.
    # If names are reused, this can end up deleting resources
    # which are not actually related.

    delete_key(name) rescue LOGGER.warn("Error deleting PK: #{$!} at #{$@}")
    LOGGER.info('Deleted PK')

    delete_group_policy(name) rescue LOGGER.warn("Error deleting policy: #{$!} at #{$@}")
    LOGGER.info('Deleted policy')

    delete_group(name) rescue LOGGER.warn("Error deleting group: #{$!} at #{$@}")
    LOGGER.info('Deleted group')

    terminate_instances_by_key(name) rescue LOGGER.warn("Error terminating EC2 instances: #{$!} at #{$@}")
    LOGGER.info('Terminated EC2 instances')

    elb_names(name).each do |elb|
      delete_elb(elb) rescue LOGGER.warn("Error deleting ELB: #{$!} at #{$@}")
    end
    LOGGER.info('Deleted ELB')

    delete_dns_cname_records(zone_id, cname_pair(name)) rescue LOGGER.warn("Error deleting CNAME: #{$!} at #{$@}")
    LOGGER.info('Deleted CNAMEs')

    # TODO: delete snapshot
  end
end
