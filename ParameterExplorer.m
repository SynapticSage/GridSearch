classdef ParameterExplorer < handle
	% Author: Ryan Y
	%
	% The purpose of this class is to define a super simplistic suite for
	% running Filter/NQ scripts or even functions with different sets of
	% parameter; a simple way to run your standard analysis with different
	% variable choices.  You just plug in the name of the thing you want to
	% run and a struct whose fields contain the parameters and values you
	% want to iterate that script over. And shazaam, you can walk away and
	% go get a coffee (or a mai tai).
    %
    % Now actually saves progress with tags! You can actually name the tags
    % sensible things to differentiate your runs.
    %
    % TODO : Need a better way of parallel jobs reporting errors, instead
    % of relying on the job to still be on the stack after runs, or
    % checking the file diary. TODO : Add ability to iterate over pool
    % vector. Pool should contain a vector of pool objects who are each
    % tied to either a local core or a cluster object's core. TODO : Add
    % ability to poll cluster for number of cpus and automatically create a
    % vector  of pool objects for 1/2(cpuNumber).
	% TODO : Add ability to give computer SSH targets, to get other
	% computers to run scripts on this. Distributed computing toolbox is
	% thousands of dollars, and it's just easier to get around it by
	% distributing work through SSH ... number 
    % TODO : Add mode for creating/controlling script send into Brandeis's
    % cluster TODO : Add cancel callback function in multiWaitbar, so user
    % can run other things and come back where left off in
    % ParameterExplorer BETATESTING : Add support for common workspace input,
    % i.e., constant variables given to all sets all sets TODO : Make mode
    % where write a function or script per set
	%% Public Properties
	properties
		% --------------------------------------------------------------------
		
		% Primary Properties
		scriptname					% Name of the script to run (over and over with different parameters)!
		paramspace=struct()			% Struct with fields that specifiy which parameters to iterate on (as struct fields) and whose values is a cell of parameters to try
		constspace=struct()
		workspace					% Struct whose fields define variables that should show up in the workspace of all separate simulations/scriptcalls, no matter the parameter set.
		% --------------------------------------------------------------------
		
		% Parallel/Series Properties
		maxjobcount=1				% Max number of iterations of the script to run
		pool=[]						% Parallel pool passed in (otherwise, defaults to standard), each pool element will represent parallel corepairs or clustersets available per parallel simulation. If not specified, assigns one core/cluster per simulation.
		useparallel=true			% Determines whether or not to use parallel/cluster processing, even if available on the system -- often its good to disable parallel processing for debugging ...
		
		% --------------------------------------------------------------------
		
		% Explorer Behavior Properties
		remember=true	% This property controls whether or not parameter explorer remembers the last valid completed parameter computation ... if it crashes during an extremely long parameter set, it remembers where it left off, and you only have to initiate .run() to start again
		% Explorer Path Proprty
		projectfolder=''; % Controls the root folder system where you parameter-dependent output folders will get created -- outputs of script calls go into parameter-dependent folders inside of the root folder, along with diary output per script call.
		
		% --------------------------------------------------------------------
	end
	%% Private Properties
	properties (SetAccess = private, Hidden = true)
		% --------------------------------------------------------------------
		indicesPerParameter
		% --------------------------------------------------------------------
		has_paralleltoolbox
		% --------------------------------------------------------------------
		% used to handle saved progress ... 
		finished_computation=false;
		lastvalid       = 0;
        sessionsID      ='FFFFFFFF';
        % used to determine file name for saved information per folder
        diaryFile       ='diary.log';
	end
	%% Public methods -- only ones user needs to know
	methods
		% --------------------------------------------------------------------
		% Contructors
		% --------------------------------------------------------------------
		function this = ParameterExplorer(scriptname,paramspace,varargin)
			% Parse the optional arguments
			
			if ~isempty(varargin)
				this = parseVarargin(this,varargin);
			end
			
			% Add the main two arguments, the name of the script we're
			% going to be running over and over again with the parameter
			% combinations in the paramspace
			this.scriptname = scriptname;
			this.paramspace = paramspace;
			
			% Here, we're counting the number of items for each parameter
			% to try out, and storing it in our object

			this.indicesPerParameter = this.getIndicesPerParameter();
			
			% Determine if the user has parallel toolbox or not
			if exist('batch.m','file') && exist('parfeval.m','file')
				this.has_paralleltoolbox = true;
				import java.lang.*;
				r=Runtime.getRuntime;
				ncpu=r.availableProcessors;
				if ncpu > 2
					%obj.pool = gcp;
                    this.maxjobcount = ncpu;
                end
			else
				this.has_paralleltoolbox = false;
            end
            
            % Generate ID for storing information in folder about which
            % parameter explorer session's sets finished
            this.sessionsID = dec2hex(round(1e6*rand(1)));
            this.diaryFile = ['diary_' this.sessionsID  '.log'];
			
			% If user provided a set of constants, to additionally set at
			% the outset of scripts (immuted between runs), then write
			% those in if a parameter file is provided
			if ~isempty(this.projectfolder)
				this.recordConstants(this.projectfolder);
			end
		end
		% --------------------------------------------------------------------
		% Mutators
		% --------------------------------------------------------------------
		function this = addParameter(this,paramName, cellOfVals)
			this.paramspace.(paramName) = cellOfVals;
        end
        % --------------------------------------------------------------------
		function this = removeParameter(this,paramName)
			this.paramspace = rmfield(this.paramspace,paramName);
        end
        % --------------------------------------------------------------------
        function this = setSessionID(this,ID)
            % Method used for starting back up previous sessions ... just
            % need an ID number
            this.sessionsID = ID;
            this.diaryFile = ['diary_' this.sessionsID  '.log'];
        end
        function this = setProjectFolder(this,projectfolder)
            this.projectfolder=projectfolder;
        end
		% --------------------------------------------------------------------
		% Set a cluster or cores for parallel computing
		% --------------------------------------------------------------------
		function this = setParallel(this,pool,jobCount)
			this.pool = pool;
			this.maxjobcount = jobCount;
		end
		% --------------------------------------------------------------------
		% Execute!
		% --------------------------------------------------------------------
		function jobs = run(this)
			tic
            
            fprintf('Starting session ID: %s\n',this.sessionsID);
            
			if ~this.remember
				this.reset();
			end
            
			if this.has_paralleltoolbox && this.useparallel
				jobs = this.run_parallel();
			else
				this.run_normal();
                jobs = [];
            end
            
            if exist('multiWaitbar.m','file')
                multiWaitbar('CloseAll');
            end
			
            toc
        end
        % --------------------------------------------------------------------
		function state = finished(this)
			state = this.finished_computation;
        end
        % --------------------------------------------------------------------
		function this = reset(this)
			this.lastvalid = 0;
		end
	end
	%% Private Methods General
	methods (Access = private)
		% -----------------------------------------------------------------
		% Variable Argument Parsing
		% -----------------------------------------------------------------
		function this = parseVarargin(this,vararg)
			for i = 1:2:numel(vararg)
				switch vararg{i}
					case 'pool'			, this.pool = vararg{i+1};
					case 'consts'		, this.constspace = vararg{i+1};
					case 'maxjobcount'	, this.maxjobcount = vararg{i+1};
					case 'projectfolder', this.projectfolder=vararg{i+1};
					otherwise
						warning('ParameterExplorer: Unrecognized variable input');
				end
			end
		end
		% -----------------------------------------------------------------
		% Index and Parameter Selection Methods
		% -----------------------------------------------------------------
		function paramcounts = getIndicesPerParameter(this)
			if isempty(this.paramspace)
				error('ParamaeterExplorer: No parameters to find indices of');
			end
			
			fields = fieldnames(this.paramspace);
			for f = 1:numel(fields)
				paramcounts{f} = ...
					numel(this.paramspace.(fields{f}));
			end
        end
        % -----------------------------------------------------------------
		function subsmat = getSubs(this)
			indexlist = this.indicesPerParameter;
			indexlist = cellfun(@(x) 1:x, indexlist,'UniformOutput',false);
			
			meshGridOutputs = cell(1,numel(fieldnames(this.paramspace)));
			[meshGridOutputs{:}] = ndgrid( indexlist{:});
			meshGridOutputs = cellfun( @(x) reshape(x,[],1), meshGridOutputs,...
				'UniformOutput',false);
			subsmat = cell2mat(meshGridOutputs);
        end
        % -----------------------------------------------------------------
		function parameter_subset = singleSet(this,combination_subscript)
			cs = combination_subscript;
			parameter_subset = struct();
			fields = fieldnames(this.paramspace);
			for f = 1:numel(fields)
				 parameter_subset.(fields{f}) = ...
					 this.paramspace.(fields{f}){cs(f)};
			end
        end
        % -----------------------------------------------------------------
		% Job Queue Methods -- Local Parallel
		% -----------------------------------------------------------------
        function processJobs(this,job,set_total,workSpace)
            
            terminus = min(numel(job),this.lastvalid+this.maxjobcount);
            nJobsWait = terminus - this.lastvalid;
            fprintf('\nWaiting for %d jobs to finish ...\n',...
               nJobsWait);
           
           % Iterate over the jobs, waiting for them to complete, then
           % storing their text output, and leaving a tag to mark
           % completion in the folder
            for i = this.lastvalid+1:terminus
                % Pre-process
                savedir = ParameterExplorer.savelocation(workSpace(i).params);
                warning off; delete(fullfile(savedir,this.diaryFile)); warning on;
                % Wait for job ...
                wait(job{i},'finished');
                % If multiwaitbar exists, UPDATE
                if exist('multiWaitbar.m','file')
                    warning off;
                    multiWaitbar([this.scriptname ': JobCompletion'],...
                        i/set_total);
                    warning on;
                end
                % Setup special diary file log ...
                diary(job{i},fullfile(savedir,this.diaryFile));
                diary(job{i}); diary off;
                % Mark job as completed
                this.markFile(workSpace(i).params);
                % Delete the job
                delete(job{i});
            end
            
        end
        % -----------------------------------------------------------------
        function exceptionInJobs(this,job,exception)
            
            warning(['Likely ran out of memory ... ' ...
                'lowering max job count']);
            
            if ~isempty(job)
                for i = 1:numel(job)
                    if job{i}.isvalid && ...
                            isequal(job{i}.State,'finished')
                        this.lastvalid = i; delete(job{i});
                    end
                end
            end
            
            clear('jobs');
            if ~isempty(this.pool)
                % re-initialize
            end
            this.exceptionHandler(exception);
        end
        % -----------------------------------------------------------------
		% Save File Methods
		% -----------------------------------------------------------------
        function markFile(this,paramset)
            savedir = ParameterExplorer.savelocation(paramset);
            fclose(fopen(fullfile(savedir,...
                ['CompletedID_' this.sessionsID]),'w'));
        end
        % -----------------------------------------------------------------
        function completedStatus = checkFile(this,paramset)
            savedir = ParameterExplorer.savelocation(paramset,...
                'projectfolder',this.projectfolder);
            completedStatus = ...
                exist(fullfile(savedir,...
                ['CompletedID_' this.sessionsID]),'file');
            if completedStatus
                fprintf('Already processed: %s\n',savedir);
                fprintf('Skipping ...\n');
            end
		end
		% -----------------------------------------------------------------
		function recordConstants(this,folder)
			
			filename=[this.sessionsID '_constants.log'];
			f=fopen(fullfile(folder,filename));
			
			for c = fields(this.constspace)
				
				if ischar(this.constspace.(c))
					right_hand_side = this.constspace.(c);
				elseif isnumeric(this.constspace.(c)) ...
						|| islogical(this.constspace.(c))
					right_hand_side = num2str(this.constspace.(c));
				end
				
				left_hand_side = c;
				
				this_const = [left_hand_side '=' right_hand_side];
				
				fwrite(f,this_const);
			end
			
			fclose(f);
		end
        %% Private Methods - Run Types
		% --------------------------------------------------------------------
		% Versions of the run function
		% For parallel and non-parallel, for scripts and functions
		% --------------------------------------------------------------------
		function job = run_parallel(this)
			
			fprintf('\nCreating jobs for parameter set: ');
			jobcount = 0;
			
            %% Acquire Parameter sets to iterate
            % acquire set total for either of the two modes
			combination_mode = numel(this.paramspace) == 1;
			if combination_mode
                parameter_combos = this.getSubs();
                set_total = size(parameter_combos,1);
			else %permutation mode
				set_total = numel(this.paramspace);
            end
			%% Setup current location
            % set the current computation to the last valid computation
			current = this.lastvalid;
			if current == set_total
				warning(['Batching already finished! Use reset method if you' ...
					'would like to start again']);
            end
            
            %% Iterate over the jobs
            try
            % iterate over remaining computations 
			while current < set_total

				% Increment counters and print current iteration
				current=current+1;
				fprintf(' %d',current);
                
                % If multiwaitbar exists, update
                if exist('multiWaitbar.m','file')
                    warning off;
                    multiWaitbar([this.scriptname ': Batching'],...
                        current/set_total);
                    warning on;
                end

				% Setup workspace to feed into batch job
				if combination_mode
					workSpace(current).params = ...
                        this.singleSet(parameter_combos(current,:));
				else
					workSpace(current).params = this.paramspace(current);
                end
                if ~isempty(this.projectfolder)
                    workSpace(current).projectfolder=this.projectfolder;
                end
                
                % If its been processed in this session, continue to next
                % cyle in loop
                if this.checkFile(workSpace(current).params)
                    this.lastvalid=current;
                    continue;
				end
				
				% Add constant variables if user provided them
				if ~isempty(fields(this.constspace))
					pairs = [fields(workSpace.params), struct2cell(workSpace.params); ...
						fields(this.constspace), struct2cell(this.constspace)]';
					workSpace.params=struct(pairs{:});
				end
				
				% Make sure folder exists, so that can save diary output
				savedir = ...
                    ParameterExplorer.savelocation(workSpace(current).params,...
					'projectfolder',this.projectfolder,'nested',true);
				warning off; mkdir(savedir); warning on;
				
				% Send job to batch
				job{current} = batch(this.scriptname,...
					'Workspace',workSpace(current),'CaptureDiary',true);
                jobcount=jobcount+1;
				
				% If we exceed job limit, wait for jobs to finish and
				% delete them.
				try
                if mod(jobcount,this.maxjobcount) == 0 || ...
                        current == set_total
                    this.processJobs(job,set_total,workSpace)					   
                    this.lastvalid = current;
                end
				% Catch any exceptions usually related to exceeding memory
				% (although potentially due to other errors)
				catch exception
                    this.exceptionInJobs(job,exception);
                    jobcount = 0;
                    current = max(current - this.maxjobcount,this.lastvalid);
                    this.maxjobcount = max(ceil(this.maxjobcount-2),1);
				end

            end
            
            % Finish off the job wait
            if ~exist('jobs','var') || isempty(job)
                job = [];
            else
                this.processJobs(job,set_total,workSpace)					   
                this.lastvalid = current;
            end
            
            catch E
                warning('\nExiting early, storing location ...\n');
                rethrow(E);
            end
            
            %% Final steps
            
            if exist('multiWaitbar.m','file')
                multiWaitbar([this.scriptname ': JobCompletion'],...
                    'Close');
                 multiWaitbar([this.scriptname ': Batch'],...
                    'Close');
            end
            
        end
        % --------------------------------------------------------------------
        function run_normal(this)
			
			if numel(this.paramspace)
				parameter_combos = this.getSubs();

				for c = 1:size(parameter_combos,1)
                    % objtain a parameter combination
					params = this.singleSet(parameter_combos(c,:));
                    % if already completed for this session, iterate!
                    if this.checkFile(params)
                        continue;
                    end
                    
                    % setup diary
                    savedir=ParameterExplorer.savelocation(params, ...
                        'projectfolder',this.projectfolder);
                    warning off; mkdir(savedir); warning on;
                    diary(fullfile(savedir,this.diaryFile));
                    
                    % assign project folder if set
                    if ~isempty(this.projectfolder)
                        assignin('base','projectfolder',this.projectfolder);
					end
					
					% add constant variables if user provided them
					if ~isempty(fields(this.constspace))
						pairs = [fields(params), struct2cell(params); ...
							fields(this.constspace), struct2cell(this.constspace)]';
						params=struct(pairs{:});
					end

                    % assign the parameter combination in the base scope
                    % and run the script in the base scope
					assignin('base','params',params);
					evalin('base', this.scriptname);
                    
                    % remember the last valid computed entry
                    this.lastvalid=c;
                    
                    % mark completion
                    this.markFile(params);
                    diary off;
				end
			else
				for p = 1:size(this.paramspace)
                    % obtain a parameter permutation
					params = this.paramspace(p);
                     % if already completed for this session, iterate!
                    if this.checkFile(params)
                        continue;
                    end
					
                    % setup diary
                    savedir=ParameterExplorer.savelocation(params, ...
                        'projectfolder',this.projectfolder);
                    warning off; mkdir(savedir); warning on;
                    diary(fullfile(savedir,this.diaryFile));
					
					% assign project folder if set
                    if ~isempty(this.projectfolder)
                        assignin('base','projectfolder',this.projectfolder);
					end
					
					% add constant variables if user provided them
					if ~isempty(fields(this.constspace))
						pairs = [fields(params), struct2cell(params); ...
							fields(this.constspace), struct2cell(this.constspace)]';
						params=struct(pairs{:});
					end
                    
                    % assign the parameter combination in the base scope
                    % and run the script in the base scope
					assignin('base','params',params);
					evalin('base',this.scriptname);
                    
                    % remember the last valid computed entry
                    this.lastvalid=p;
                    
                    % mark completion
                    this.markFile(params);
                    diary off;
                end
            end
            
            % If multiwaitbar exists, update
            if exist('multiWaitbar.m','file')
                multiWaitbar('CloseAll');
            end
            
        end
		% --------------------------------------------------------------------
		% Exception Handling
		% --------------------------------------------------------------------
		function exceptionHandler(~,exception)
			assignin('base','ParameterExplorer_exception',exception);
            
%             if exist('cprintf.m','file')
%                 pf = @(x,y,z) cprintf('red', x,y,z);
%             else
%                 pf = @fprintf;
%             end
            
            fprintf('Found exception ');
            for i = 1:numel(exception.stack.line)
                fprintf('in %s on %s ...\n', ...
                    exception.stack(i).file, exception.stack(i).line);
            end
		end
	end
	%% Public Static Methods
	methods (Access = public, Static = true)
		function swapParamSet(params)
			% When called in a script, it swaps in the parameter
			% combination, which can be done right before any of the main
			% processing.
			if ~isstruct(params)
				error('ParameterExplorer: Struct required!');
			end
			
			fields = fieldnames(params);
			for f = 1:numel(fields)
				assignin('caller',fields{f},params.(fields{f}));
			end
		end
		function savedir = savelocation(paramset,varargin)
			% Genereates savefolder names/directories automatically for a
			% particular parameter set. This will aid in automatically
			% determining an organized system of saves when exploring a
			% large sequence of parameters.
			
			persistent projectfolder;
			nested = true;
			
			for i = 1:2:numel(varargin)
				switch(varargin{i})
					case 'nested', nested = varargin{i+1};
					case 'projectfolder', projectfolder = varargin{i+1};
					otherwise warning('Unrecognized input');
				end
			end
			
            % intialize string to build
			savedir = '';
			
            % get fields on which to create directory structure
			fields = fieldnames(paramset);
			
			% compute the directory name
			for f = 1:numel(fields)
				
				value = paramset.(fields{f});
				if isnumeric(value) || ischar(value) || islogical(value)
					if isnumeric(value) || islogical(value); value=num2str(value); end;
                else
                    warning('ParameterExplorer: field %s cannot be factored into save directory structure',fields{f});
					continue;
                end
                if isempty(value)
                    value='NULL';
                end
					
				if nested
					savedir=[savedir fields{f} '=' value filesep];
				else
					savedir=[savedir fields{f} '=' value, ','];
				end
            end
            savedir(end)=filesep;
            
            % remove any spaces
            savedir=strrep(savedir,' ','-');
			
            % add project folder
			savedir=fullfile(projectfolder, savedir);
			
        end
	end
end
