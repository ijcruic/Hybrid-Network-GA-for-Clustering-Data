function [final_subgroups, latent_network, output] = HybdridNetworkGA(A, metric)

%% Main Program. Set optimization parameters for GA solver, record output, and get the final Phenotype %%

lb = ones(size(A,1),1);
ub = size(A,1) .* ones(size(A,1),1)-1;
Distance = squareform(pdist(A, metric));
Distance(logical(eye(size(Distance)))) =Inf;
[~, nearestNeighbors] = sort(Distance, 2);

opts = gaoptimset('CrossoverFcn', @uniform_cross, ...
                    'MutationFcn',  @indegree_mut,'CreationFcn', @uniform_init,...
                    'SelectionFcn', @selectiontournament, 'UseParallel', true);

[x, fval, exitflag, Output] = ga(@evaluationFunction, size(A,1), [], [],[],[],lb,ub,[],[],opts);

output.x = x;
output.fval = fval;
output.exitflag =exitflag;
output.Output = Output;

[final_subgroups, latent_network] = findFinalSolution(x, 'assym_eval');

    %% Evaluation Function %%

    function result = evaluationFunction(x)
        G = digraph();
        G = addnode(G, size(A,1));
        [s, t] = arrayfun(@(i) constructEdges(i, x(i)), 1:size(A,1), 'UniformOutput', false);
        G = addedge(G, cell2mat(s), cell2mat(t));
        G = adjacency(G);
        subgroups = GCModulMax1(G);
        result = -1 * (QFModul(subgroups, G)-ERModularity(G));      
    end
    
    %% Helper function to construct networks from a genotype of nearest neighbors for each indice %%

    function [s, t] = constructEdges(i, local_k)
        smallestNIdx = nearestNeighbors(i, 1:local_k);
        s=i.*ones(1, numel(smallestNIdx));
        t=smallestNIdx;        
    end

    %% Helper function to create null-model modularity from an Erdos-Renyi random graph %%
    
    function [modularity] = ERModularity(G)
        S = size(G,1);
        p = nnz(G)/ numel(G);
        modularity = (1-2/sqrt(S))*(2/(p*S))^(2/3);
    end

    %% Genetic Operators %%
    
    function Population = uniform_init(Genomelength, FitnessFcn, options)
        pop_size = options.PopulationSize;
        
        Population = randi([1,size(A,1)-1], pop_size, size(A,1));
    end

    function Population = zeta_init(Genomelength, FitnessFcn, options)
        pop_size = options.PopulationSize;

        Population = randraw('zeta', 3, pop_size, size(A,1));
        Population(Population > size(A,1)-1) = size(A,1)-1;
    end

    function xoverKids = one_point_cross(parents, options, nvars, FitnessFcn, ...
        unused,thisPopulation)

        xoverKids = [];
        for idx = 1:2:numel(parents)-1
            i = parents(idx);
            j = parents(idx+1);

            crossover_point = randi([1,size(A,1)],1,1);
            child = [thisPopulation(i, 1:crossover_point), thisPopulation(j, crossover_point+1:end)];
            xoverKids = [xoverKids; child];

        end
        
    end

    function xoverKids = uniform_cross(parents, options, nvars, FitnessFcn, ...
        unused,thisPopulation)

        xoverKids = [];
        for idx = 1:2:numel(parents)-1
            i = parents(idx);
            j = parents(idx+1);
            
            crossover_mask = randi([0,1],1,size(A,1));
            child = thisPopulation(i, :) .* crossover_mask + thisPopulation(j,:) .* (1-crossover_mask);
            xoverKids = [xoverKids; child];
            
        end
        
    end

    function mutationChildren = uniform_mut(parents, options, nvars, FitnessFcn, ...
        state,thisScore, thisPopulation, rate)
        
        mutationChildren  = thisPopulation(parents, :);
        num_elements = ceil(rate*size(mutationChildren,2));
        for i = 1:size(mutationChildren, 1)
            indices_to_mutate = randperm(size(mutationChildren,2),num_elements);
            mutationChildren(i, indices_to_mutate)= randi([0,size(A,1)-1],1,numel(indices_to_mutate));
        end
        
    end

    function mutationChildren = zeta_mut(parents, options, nvars, FitnessFcn, ...
        state,thisScore, thisPopulation, rate)
        
        mutationChildren  = thisPopulation(parents, :);
        num_elements = ceil(rate*size(mutationChildren,2));
        for i = 1:size(mutationChildren, 1)
            indices_to_mutate = randperm(size(mutationChildren,2),num_elements);
            mutationChildren(i, indices_to_mutate)= randraw('zeta', 3, 1,numel(indices_to_mutate));
        end
        mutationChildren(mutationChildren > size(A,1)-1) = size(A,1) -1;
    end

    function mutationChildren = indegree_mut(parents, options, nvars, FitnessFcn, ...
        state,thisScore, thisPopulation)
        
        mutationChildren  = thisPopulation(parents, :);
        
        for i = 1:size(mutationChildren, 1)
            G = digraph();
            G = addnode(G, size(A,1));
            [s, t] = arrayfun(@(j) constructEdges(j, mutationChildren(j)), 1:size(A,1), 'UniformOutput', false);
            G = addedge(G, cell2mat(s), cell2mat(t));
            centralities = centrality(G, 'indegree');
            [values,nodes] = sort(centralities);
            bottomNodes = nodes(1:size(values( values < mean(values) - std(values)),1));
            mutationChildren(i, bottomNodes) = arrayfun(@(x) randi([1,x],1,1), mutationChildren(i, bottomNodes));
            [values,nodes] = sort(centralities, 'descend');
            topNodes = nodes(1:size(values( values > mean(values) + std(values)),1));
            mutationChildren(i, topNodes) = arrayfun(@(x) randi([x,size(A,1)-1],1,1), mutationChildren(i, topNodes));
        end
        % mutationChildren(mutationChildren > size(A,1)-1) = size(A,1) -1;
    end

    %% Creating final solution %%

    function [subgroups, G] = findFinalSolution(x, network_type)
        G = digraph();
        G = addnode(G, size(A,1));
        [s, t] = arrayfun(@(i) constructEdges(i, x(i)), 1:size(A,1), 'UniformOutput', false);
        G = addedge(G, cell2mat(s), cell2mat(t));

        if strcmp(network_type,'sym_eval')
            g_adjacency = adjacency(G) .* adjacency(G)';
            G = graph(g_adjacency);
        else
            g_adjacency = adjacency(G);
        end
        subgroups = GCModulMax1(g_adjacency);
    end
end