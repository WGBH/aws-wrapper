require_relative 'base_wrapper'
require 'json'
require 'uri'

module IamWrapper
  include BaseWrapper

  def create_group(name)
    iam_client.create_group( # path: optional
      group_name: name).group
  end

  def delete_group(group_name)
    list_users_in_group(group_name).each do |user_name|
      iam_client.remove_user_from_group(
        group_name: group_name, # required
        user_name: user_name, # required
      )
    end
    iam_client.delete_group( # path: optional
      group_name: group_name)
  end

  def add_user_to_group(user_name, group_name)
    iam_client.add_user_to_group(
      group_name: group_name, # required
      user_name: user_name, # required
    )
    LOGGER.info("Added #{user_name} to #{group_name}")
  end

  def add_current_user_to_group(group_name)
    add_user_to_group(current_user_name, group_name)
  end

  def lookup_groups_by_resource(arn_fragment)
    groups = group_resources_hash.keys
    groups.select do |group|
      matching_resources = group_resources_hash[group].select do |resource|
        resource.include?(arn_fragment)
      end
      !matching_resources.empty?
    end
  end

  def put_group_policy(group_name, statement)
    iam_client.put_group_policy(
      group_name: group_name, # required
      policy_name: group_name, # required
      policy_document: {
        'Version' => '2012-10-17',
        'Statement' => statement
      }.to_json, # required
    )
  end

  def delete_group_policy(group_name)
    iam_client.delete_group_policy(
      group_name: group_name, # required
      policy_name: group_name # required
    )
  end

  private

  def iam_client
    @iam_client ||= Aws::IAM::Client.new(client_config)
  end

  def current_user_name
    @current_user_name ||= Aws::IAM::CurrentUser.new.user_name
  end

  def list_users_in_group(group_name)
    iam_client.get_group(
      group_name: group_name # required
      # marker: "markerType",
      # max_items: 1,
    ).users.map(&:user_name)
  end

  def group_resources_hash
    @group_resources_hash ||= Hash[
      iam_client.list_groups.groups.map(&:group_name).map do |group_name|
        resources = iam_client.list_group_policies(group_name: group_name).policy_names.map do |policy_name|
          json_encoded = iam_client.get_group_policy(group_name: group_name, policy_name: policy_name).policy_document
          policy = JSON.parse(URI.decode(json_encoded))
          statement = policy['Statement']
          statements = if statement.class == Array
                         statement
                       else
                         [statement]
                       end
          statements.map { |s| s['Resource'] }
        end
        [group_name, resources.flatten]
      end
    ]
  end
end
