# ParameterExplorer class
Ie how to grid search your scripts over parallel cores without significantly rewriting your codes.

## How to use this

Imagine someone gives you a matlab script and you would like to explore that script by changing some of it's variables in various combinations.

For example, suppose a colleague sends me a script, `DFS_ChoiceCoherence.m`. And in that script I see 6 variables I would like to sweep over all possible combinations, exploring them automatically with parallel cores, without rewriting it much. I can specify the script and variables as follows.

```matlab
scriptname = 'DFS_ChoiceCoherence';
params = struct( ...
	'brain_area',       {{ 3 }},                        ... // Which brain regions types to look at
	'segment_identity', {{ 1,4,2 }},                    ... // Which track segment to analyze
    'trajbound',        {{'0','1'}},                    ... // outbound or inbound
    'rewarded',         {{'0','1'}},                    ... // Whether or not the trajectory was rewarded
	'temporal_window',	{{ 2 }},						... // How big to make the temporal window
    'fpass',            {{[0 150]}} ... [0 40],[25 100] }}    ... // frequencies to examine!
	); 
```

In other words, 1*3*2*2*1*1 combinations. Now we initialize a `ParameterExplorer` object, alerting it to the script and parameters. Its `parallel` attribute controls whether to use single core or multi core execution. To run, call the `run()` method.

```matlab
% Create the parmeter explorer
Explorer = ParameterExplorer(scriptname,params);
% Explorer.useparallel = false; % Uncomment this line if you would prefer it not run scripts as batches -- good for debugging!
Explorer.run(); % runs the ParameterExplorer, if it fails, 
				% or you halt it mid-run, it remembers where it stopped and 
				% can be re-initiated with .run() method where it left off.
```

## Permutations instead of Combinations

This above way of defining params struct generates a run of every possibly combination of those parameters ... if you want a specific permutation/sequence instead of all combinations, then instead of making a 1x1 array with each key's value being a cellular list of things to try, you make a 1xn array each with a single value per key. So,

```matlab
params = struct( ...
 	'type_to_examine',	{ 1,2,3 },				... 
 	'segment_identity', { 1,2,3 },				... 
 	'temporal_window',	{ 0.2,0.3,0.4 },		... 
 	'dayfilter',		{ '4:5','7','8' }		... 
 	);
```

will run through 1,1,0.2,'4:5' then 2,2,0.3,'7' then 3,3,0.4,'8', instead of all possible combinations.

## What your script requires

For ParameterExplorer to work, you only have to include the following lines in your script:

```matlab
if exist('params','var') && isstruct(params)
	ParameterExplorer.swapParamSet(params);
  savedir = ParameterExplorer.savelocation(params,projectdir,true);
end
```

ParameterExplorer calls the script and writes a structural variable called params into its scope. It then assigns the each field name and corresponding value into that scope using `.swapParmSet()` method. It then automatically creates a savedirectory structure for that parameter set, so all of the saved files in that script fall neatly into a corresponding parameter folder. So suppose the parameter set is type_to_examine=1, segment_identity=1, temporal_window=0.2, dayfilter='4:5', it creates a folder `projectdir/segment_identity=1/temporal_window=0.2/dayfilter='4:5'` where it storees data from that simulation.
