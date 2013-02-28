class ApiController < ApplicationController
skip_filter :set_current_user_and_project
	before_filter :login_once
  	before_filter do |f|
    	f.require_permission(['ADMIN'])
  	end
	respond_to :xml

	# example: Case.create_with_steps!({:created_by=>3,:updated_by=>3,:title => "Импорт", :date=>"2012-09-22T00:00:00",:priority=>"high", :time_estimate=>"", :objective=>"Цель",:test_data=>"Данные",:preconditions_and_assumptions=>"some prec",:test_area_ids=>[],:change_comment=>"Comment",:project_id=>1,:version=>1},[:version=>1,:position=>1,:action=>"step1",:result=>"res1"])
	def create_testcase
    	raise ApiError.new("Could not parse request as XML. Make sure to specify \'Content-type: text/xml\' when sending request", params.inspect) if params["request"].nil? or params["request"]["testcase"].nil?    	
		attrs = params["request"]["testcase"]
		steps = attrs["step"] 
		raise ApiError.new("Provided steps set is empty", params.inspect) if steps.nil?
		steps.each{|s| 
			s["version"] = 1
			s["position"] = steps.index(s)+1
		}
		project = Project.find_by_name(attrs["project"])		
		raise ApiError.new("Project not found", attrs["project"]) if project.nil?
		c = Case.create_with_steps!(
			{ # test attrs
				:created_by => @current_user.id,
				:updated_by => @current_user.id,
				:title => attrs[:title], 
				:date => Date.today.to_s(:db),
				:priority => attrs[:priority], 
				:objective => attrs[:objective],
				:test_data => attrs[:data],
				:preconditions_and_assumptions => attrs[:preconditions],
				:project_id => project.id,
				:version=>1
			},
			# steps
			steps,
			#tag_list
			attrs[:tags]
			)
		render :xml => { :result => "testcase #{c.title} created" }.to_xml
	end

	def update_testcase_execution
		attrs = params["request"]
    	raise ApiError.new("Could not parse request as XML. Make sure to specify \'Content-type: text/xml\' when sending request", params.inspect) if attrs.nil?
		project = Project.find_by_name(attrs["project"])
		raise ApiError.new("Project not found", attrs["project"]) if project.nil?
		# following assumptions are made:
		# validates_uniqueness_of :name, :scope => :project_id (execution.rb)
		# validates_uniqueness_of :title, :scope => :project_id (case.rb)
		testcase_execution = CaseExecution.find_by_execution_id_and_case_id(project.executions.where(:name => attrs["execution"]).first, project.cases.where(:title => attrs["testcase"]).first)
		raise ApiError.new("CaseExecution not found", "Test => #{attrs["testcase"]}, Execution => #{attrs["execution"]}") if testcase_execution.nil?
		step_results = []
		attrs["step"].each{|se|
			te = testcase_execution.step_executions.where(:position => se["position"].to_i)
			raise ApiError.new("Case step with position #{se["position"].to_i} not found inside testcase #{attrs["testcase"]}", "Steps => #{testcase_execution.step_executions.collect(&:inspect)}") if te.empty?
			step_result = {}
			step_result["id"] = testcase_execution.step_executions.where(:position => se["position"].to_i).first.id
			step_result["result"] = se["result"]
			step_result["comment"] = se["comment"]
			step_result["bug"] = nil
			step_results << step_result
		}
		testcase_execution.update_with_steps!({"duration" => attrs["duration"]},step_results,@current_user)
		render :xml => { :result => "execution #{attrs["execution"]} updated" }.to_xml
	end
	def block_testcase_execution
		attrs = params["request"]
    	raise ApiError.new("Could not parse request as XML. Make sure to specify \'Content-type: text/xml\' when sending request", params.inspect) if attrs.nil?
		testcase_execution = block_unblock(true,attrs)
		render :xml => { :result => "execution #{attrs["execution"]} blocked" } 
	end

	def unblock_testcase_execution
		attrs = params["request"]
    	raise ApiError.new("Could not parse request as XML. Make sure to specify \'Content-type: text/xml\' when sending request", params.inspect) if attrs.nil?
		testcase_execution = block_unblock(false, attrs)
		render :xml => { :result => "execution #{attrs["execution"]} unblocked" }
	end

	private
	def login_once
		authenticate_or_request_with_http_basic do |username, password|
      		if can_do_stuff?(username,password)
				set_current_user_and_project
			end
		end
	end


	def block_unblock(flag,attrs)
		project = Project.find_by_name(attrs["project"])
		raise ApiError.new("Project not found", attrs["project"]) if project.nil?
		# following assumptions are made:
		# validates_uniqueness_of :name, :scope => :project_id (execution.rb)
		# validates_uniqueness_of :title, :scope => :project_id (case.rb)
		testcase_execution = CaseExecution.find_by_execution_id_and_case_id(project.executions.where(:name => attrs["execution"]).first, project.cases.where(:title => attrs["testcase"]).first)
		raise ApiError.new("Case execution not found", "Test => #{attrs["testcase"]}, Execution => #{attrs["execution"]}") if testcase_execution.nil?
		testcase_execution.update_attribute(:blocked, flag)
		testcase_execution
	end
end
