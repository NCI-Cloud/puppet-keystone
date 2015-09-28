require 'puppet/provider/keystone'

Puppet::Type.type(:keystone_tenant).provide(
  :openstack,
  :parent => Puppet::Provider::Keystone
) do

  desc "Provider to manage keystone tenants/projects."

  @credentials = Puppet::Provider::Openstack::CredentialsV3.new

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  def create
    # see if resource[:domain], or project_name::project_domain
    project_name, project_domain = self.class.name_and_domain(resource[:name], resource[:domain])
    properties = [project_name]
    if resource[:enabled] == :true
      properties << '--enable'
    elsif resource[:enabled] == :false
      properties << '--disable'
    end
    if resource[:description]
      properties << '--description'
      properties << resource[:description]
    end
    if project_domain
      properties << '--domain'
      properties << project_domain
    end
    @property_hash = self.class.request('project', 'create', properties)
    @property_hash[:name] = resource[:name]
    @property_hash[:ensure] = :present
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def destroy
    self.class.request('project', 'delete', id)
    @property_hash.clear
  end

  def enabled=(value)
    @property_flush[:enabled] = value
  end

  def enabled
    bool_to_sym(@property_hash[:enabled])
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def description
    @property_hash[:description]
  end

  def domain
    @property_hash[:domain]
  end

  def id
    @property_hash[:id]
  end

  def self.instances
    projects = request('project', 'list', '--long')
    projects.collect do |project|
      domain_name = domain_name_from_id(project[:domain_id])
      project_name = set_domain_for_name(project[:name], domain_name)
      new(
        :name        => project_name,
        :ensure      => :present,
        :enabled     => project[:enabled].downcase.chomp == 'true' ? true : false,
        :description => project[:description],
        :domain      => domain_name,
        :domain_id   => project[:domain_id],
        :id          => project[:id]
      )
    end
  end

  def self.prefetch(resources)
    project_hash = {}
    projects = instances
    resources.each do |resname, resource|
      # resname may be specified as just "name" or "name::domain"
      name, resdomain = name_and_domain(resname, resource[:domain])
      provider = projects.find do |project|
        # have a match if the full instance name matches the full resource name, OR
        # the base resource name matches the base instance name, and the
        # resource domain matches the instance domain
        project_name, project_domain = name_and_domain(project.name, project.domain)
        (project.name == resname) ||
          ((project_name == name) && (project_domain == resdomain))
      end
      resource.provider = provider if provider
    end
  end

  def flush
    options = []
    if @property_flush && !@property_flush.empty?
      case @property_flush[:enabled]
      when :true
        options << '--enable'
      when :false
        options << '--disable'
      end
      (options << "--description=#{resource[:description]}") if @property_flush[:description]
      self.class.request('project', 'set', [id] + options) unless options.empty?
      @property_flush.clear
    end
  end
end
