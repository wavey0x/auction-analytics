import React, { useState } from 'react';
import { Search, Book, ExternalLink, Globe, Database, Activity, BarChart3, Clock } from 'lucide-react';
import ApiEndpoint from '../components/ApiEndpoint';
import CodeBlock from '../components/CodeBlock';

const ApiDocs: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');

  // API Endpoint Definitions
  const endpoints = [
    // Core Auction Endpoints
    {
      category: 'core',
      title: 'Get Auctions',
      method: 'GET' as const,
      endpoint: '/auctions',
      description: 'Retrieve a paginated list of all auctions with optional filtering by status and chain.',
      parameters: [
        { name: 'status', type: 'string' as const, enum: ['all', 'active', 'completed'], description: 'Filter auctions by their current status' },
        { name: 'page', type: 'integer' as const, description: 'Page number for pagination', example: 1 },
        { name: 'limit', type: 'integer' as const, description: 'Number of auctions per page (1-100)', example: 20 },
        { name: 'chain_id', type: 'integer' as const, description: 'Filter auctions by blockchain network', example: 1 },
      ],
      responses: [
        {
          status: 200,
          description: 'Successfully retrieved auctions',
          example: {
            auctions: [
              {
                address: '0x1234567890abcdef1234567890abcdef12345678',
                chain_id: 1,
                from_tokens: [{ symbol: 'WETH', address: '0x...', decimals: 18 }],
                want_token: { symbol: 'USDC', address: '0x...', decimals: 6 },
                current_round: {
                  round_id: 5,
                  is_active: true,
                  initial_available: '1000000000000000000',
                  time_remaining: 3600
                }
              }
            ],
            total: 50,
            page: 1,
            per_page: 20,
            has_next: true
          }
        }
      ],
      codeExamples: {
        curl: `curl -X GET "${window.location.origin}/api/auctions?status=active&limit=10" \\
  -H "Content-Type: application/json"`,
        javascript: `const response = await fetch('/api/auctions?status=active&limit=10');
const data = await response.json();
console.log(data.auctions);`,
        python: `import requests

response = requests.get('${window.location.origin}/api/auctions', 
                       params={'status': 'active', 'limit': 10})
data = response.json()
print(data['auctions'])`
      },
      tags: ['auctions', 'core']
    },
    // Core (Auctions)
    {
      category: 'core',
      title: 'Get Auction Details',
      method: 'GET' as const,
      endpoint: '/auctions/{auction_address}',
      description: 'Get specific auction by address (provide chain_id as query parameter).',
      pathParams: [{ name: 'auction_address', type: 'string' as const, required: true }],
      parameters: [{ name: 'chain_id', type: 'integer' as const, required: true }],
      responses: [{ status: 200, description: 'Auction details', example: { address: '0x123...789', chain_id: 1 } }],
      tags: ['auctions']
    },
    {
      category: 'core',
      title: 'Get Auction Config',
      method: 'GET' as const,
      endpoint: '/auctions/{auction_address}/config',
      description: 'Get auction parameters (provide chain_id as query parameter).',
      pathParams: [{ name: 'auction_address', type: 'string' as const, required: true }],
      parameters: [{ name: 'chain_id', type: 'integer' as const, required: true }],
      responses: [{ status: 200, description: 'Auction config', example: { decay_rate: 0.005, update_interval: 36 } }],
      tags: ['auctions']
    },
    {
      category: 'core',
      title: 'Get Auction Rounds',
      method: 'GET' as const,
      endpoint: '/auctions/{auction_address}/rounds',
      description: 'Rounds for a specific auction (provide chain_id as query parameter).',
      pathParams: [{ name: 'auction_address', type: 'string' as const, required: true }],
      parameters: [
        { name: 'chain_id', type: 'integer' as const, required: true },
        { name: 'from_token', type: 'string' as const, description: 'Optional from-token address' },
        { name: 'round_id', type: 'integer' as const, description: 'Optional specific round' },
        { name: 'limit', type: 'integer' as const, description: 'Number of rounds', example: 50 }
      ],
      responses: [{ status: 200, description: 'Rounds list', example: { rounds: [{ round_id: 5 }], total_count: 1 } }],
      tags: ['rounds']
    },
    {
      category: 'core',
      title: 'Get Auction Takes',
      method: 'GET' as const,
      endpoint: '/auctions/{auction_address}/takes',
      description: 'Takes for a specific auction (provide chain_id as query parameter).',
      pathParams: [{ name: 'auction_address', type: 'string' as const, required: true }],
      parameters: [
        { name: 'chain_id', type: 'integer' as const, required: true },
        { name: 'round_id', type: 'integer' as const, description: 'Optional round filter' },
        { name: 'limit', type: 'integer' as const, description: 'Items per page', example: 50 },
        { name: 'offset', type: 'integer' as const, description: 'Offset for pagination', example: 0 }
      ],
      responses: [{ status: 200, description: 'Auction takes', example: { takes: [{ take_id: '0xabc...-5-1' }], total_count: 10, limit: 50, page: 1, total_pages: 1 } }],
      tags: ['takes']
    },

    // Core (Takes)
    {
      category: 'core',
      title: 'List Takes',
      method: 'GET' as const,
      endpoint: '/takes',
      description: 'List recent takes across all auctions. Use chain_id to filter to a network.',
      parameters: [ { name: 'limit', type: 'integer' as const, example: 50 }, { name: 'chain_id', type: 'integer' as const } ],
      responses: [{ status: 200, description: 'Recent takes', example: [{ take_id: '0xabc...-5-1' }] }],
      tags: ['takes']
    },
    {
      category: 'core',
      title: 'Get Take Details',
      method: 'GET' as const,
      endpoint: '/takes/{chain_id}/{auction_address}/{round_id}/{take_seq}',
      description: 'Get detailed information for a specific take.',
      pathParams: [
        { name: 'chain_id', type: 'integer' as const, required: true },
        { name: 'auction_address', type: 'string' as const, required: true },
        { name: 'round_id', type: 'integer' as const, required: true },
        { name: 'take_seq', type: 'integer' as const, required: true }
      ],
      responses: [{ status: 200, description: 'Take detail', example: { chain_id: 1, auction_address: '0x123...789', round_id: 5, take_seq: 1 } }],
      tags: ['takes']
    },

    // Core (Rounds)
    {
      category: 'core',
      title: 'List Rounds',
      method: 'GET' as const,
      endpoint: '/rounds',
      description: 'Minimal listing of recent rounds across all auctions.',
      parameters: [ { name: 'limit', type: 'integer' as const, example: 50 }, { name: 'chain_id', type: 'integer' as const } ],
      responses: [{ status: 200, description: 'Rounds', example: { rounds: [{ auction_address: '0x123...789', round_id: 5 }], total_count: 1 } }],
      tags: ['rounds']
    },
    // Reference
    // Taker Endpoints
    {
      category: 'takers',
      title: 'List Takers',
      method: 'GET' as const,
      endpoint: '/takers',
      description: 'Get ranked takers with summary stats. Supports sorting by volume, takes, or recent.',
      parameters: [
        { name: 'sort_by', type: 'string' as const, enum: ['volume','takes','recent'], description: 'Sorting mode', example: 'volume' },
        { name: 'page', type: 'integer' as const, description: 'Page number', example: 1 },
        { name: 'limit', type: 'integer' as const, description: 'Items per page (1-100)', example: 20 },
        { name: 'chain_id', type: 'integer' as const, description: 'Filter to takers active on a chain' }
      ],
      responses: [{
        status: 200,
        description: 'Takers retrieved',
        example: {
          takers: [{
            taker: '0xabc...def', total_takes: 42, unique_auctions: 5, unique_chains: 2,
            total_volume_usd: 12345.67, avg_take_size_usd: 293.94,
            first_take: '2024-01-10T00:00:00Z', last_take: '2024-01-20T12:34:56Z',
            active_chains: [1,42161], rank_by_takes: 3, rank_by_volume: 5,
            takes_last_7d: 10, takes_last_30d: 20, volume_last_7d: 2500.0, volume_last_30d: 5000.0
          }],
          total: 100, page: 1, per_page: 20, has_next: true
        }
      }],
      tags: ['takers','ranking']
    },
    {
      category: 'takers',
      title: 'Get Taker Details',
      method: 'GET' as const,
      endpoint: '/takers/{taker_address}',
      description: 'Get summary stats and ranks for a specific taker, including per-auction breakdown.',
      pathParams: [{ name: 'taker_address', type: 'string' as const, required: true }],
      responses: [{
        status: 200,
        description: 'Taker details',
        example: {
          taker: '0xabc...def', total_takes: 42, unique_auctions: 5, unique_chains: 2,
          total_volume_usd: 12345.67, avg_take_size_usd: 293.94,
          first_take: '2024-01-10T00:00:00Z', last_take: '2024-01-20T12:34:56Z',
          rank_by_takes: 3, rank_by_volume: 5, total_takers: 100,
          active_chains: [1,42161],
          auction_breakdown: [{ auction_address: '0x123...789', chain_id: 1, takes_count: 10, volume_usd: 2500.0, first_take: '2024-01-11T00:00:00Z', last_take: '2024-01-20T12:00:00Z' }]
        }
      }],
      tags: ['takers']
    },
    {
      category: 'takers',
      title: 'Get Taker Takes',
      method: 'GET' as const,
      endpoint: '/takers/{taker_address}/takes',
      description: 'Get paginated takes for a taker (most recent first).',
      pathParams: [{ name: 'taker_address', type: 'string' as const, required: true }],
      parameters: [
        { name: 'page', type: 'integer' as const, description: 'Page number', example: 1 },
        { name: 'limit', type: 'integer' as const, description: 'Items per page', example: 10 },
        { name: 'chain_id', type: 'integer' as const, description: 'Filter by chain' }
      ],
      responses: [{
        status: 200,
        description: 'Takes list',
        example: {
          takes: [{ take_id: '0xabc...-5-1', auction_address: '0x123...789', chain_id: 1, round_id: 5, take_seq: 1,
                    taker: '0xabc...def', amount_taken: '100000000000000000', amount_paid: '195000000', timestamp: '2024-01-20T12:34:56Z', tx_hash: '0xdef...',
                    from_token_symbol: 'WETH', to_token_symbol: 'USDC', from_token_price_usd: '2200.00', want_token_price_usd: '1.00', amount_taken_usd: '220.00', amount_paid_usd: '195.00' }],
          total_count: 10, page: 1, limit: 10, total_pages: 1
        }
      }],
      tags: ['takers','takes']
    },
    {
      category: 'takers',
      title: 'Get Taker Token Pairs',
      method: 'GET' as const,
      endpoint: '/takers/{taker_address}/token-pairs',
      description: 'Get most frequent from→to token pairs for a taker with USD volume.',
      pathParams: [{ name: 'taker_address', type: 'string' as const, required: true }],
      parameters: [
        { name: 'page', type: 'integer' as const, description: 'Page number', example: 1 },
        { name: 'limit', type: 'integer' as const, description: 'Items per page', example: 50 }
      ],
      responses: [{
        status: 200,
        description: 'Token pairs list',
        example: {
          token_pairs: [{ from_token: '0xWETH...', to_token: '0xUSDC...', takes_count: 7, volume_usd: 1523.22, last_take_at: '2024-01-20T12:00:00Z', unique_auctions: 3, unique_chains: 2, from_token_symbol: 'WETH', to_token_symbol: 'USDC', active_chains: [1,42161] }],
          page: 1, per_page: 50, total_count: 1, total_pages: 1
        }
      }],
      tags: ['takers','analytics']
    },

    // System Endpoints
    {
      category: 'system',
      title: 'Health Check',
      method: 'GET' as const,
      endpoint: '/health',
      description: 'Check the health status of the API service and database connectivity.',
      responses: [
        {
          status: 200,
          description: 'Service is healthy',
          example: {
            status: 'healthy',
            mode: 'dev',
            mock_mode: false,
            database: 'healthy',
            timestamp: '2024-01-15T14:30:00Z'
          }
        }
      ],
      codeExamples: {
        curl: `curl -X GET "${window.location.origin}/api/health"`,
        javascript: `const response = await fetch('/api/health');
const health = await response.json();
console.log(health.status);`
      },
      tags: ['system', 'monitoring']
    },
    {
      category: 'system',
      title: 'System Overview',
      method: 'GET' as const,
      endpoint: '/analytics/overview',
      description: 'System-wide metrics including totals and recent activity summaries.',
      parameters: [ { name: 'chain_id', type: 'integer' as const, description: 'Optional chain filter' } ],
      responses: [{ status: 200, description: 'Overview', example: { total_auctions: 150, active_auctions: 12, total_takes: 5600, total_volume_usd: 12500000.50 } }],
      tags: ['system','analytics']
    },
    {
      category: 'reference',
      title: 'Get Tokens',
      method: 'GET' as const,
      endpoint: '/tokens',
      description: 'Retrieve information about all tokens that have been used in auctions.',
      responses: [
        {
          status: 200,
          description: 'Token information retrieved successfully',
          example: {
            tokens: [
              {
                address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
                symbol: 'WETH',
                name: 'Wrapped Ether',
                decimals: 18,
                chain_id: 1
              },
              {
                address: '0xA0b86a33E6411C8D4E5DC8DF0D79E2B8Cb5D5Bfa',
                symbol: 'USDC',
                name: 'USD Coin',
                decimals: 6,
                chain_id: 1
              }
            ],
            count: 45
          }
        }
      ],
      tags: ['reference', 'tokens', 'metadata']
    },

    // Reference Endpoints
    {
      category: 'reference',
      title: 'Get Chains',
      method: 'GET' as const,
      endpoint: '/chains',
      description: 'Get information about all supported blockchain networks including chain IDs, names, and block explorers.',
      responses: [
        {
          status: 200,
          description: 'Chain information retrieved successfully',
          example: {
            chains: {
              "1": {
                chainId: 1,
                name: 'Ethereum Mainnet',
                shortName: 'Ethereum',
                icon: 'https://icons.llamao.fi/icons/chains/rsz_ethereum.jpg',
                nativeSymbol: 'ETH',
                explorer: 'https://etherscan.io'
              },
              "137": {
                chainId: 137,
                name: 'Polygon',
                shortName: 'Polygon',
                icon: 'https://icons.llamao.fi/icons/chains/rsz_polygon.jpg',
                nativeSymbol: 'MATIC',
                explorer: 'https://polygonscan.com'
              }
            },
            count: 6
          }
        }
      ],
      tags: ['reference', 'chains', 'metadata']
    },

    // Analytics Endpoints
    {
      category: 'analytics',
      title: 'Recent Takes',
      method: 'GET' as const,
      endpoint: '/takes',
      description: 'Get the most recent takes across all auctions, sorted by timestamp (newest first).',
      parameters: [ { name: 'limit', type: 'integer' as const, description: 'Number of takes to return (1-500)', example: 50 }, { name: 'chain_id', type: 'integer' as const, description: 'Filter by chain' } ],
      responses: [{ status: 200, description: 'Recent takes', example: [{ take_id: '1:0x123...789:5:1' }] }],
      tags: ['analytics','recent']
    }
  ];

  const categories = [
    { id: 'all', name: 'All Endpoints', icon: Book },
    { id: 'core', name: 'Core', icon: Database },
    { id: 'takers', name: 'Takers', icon: Activity },
    { id: 'reference', name: 'Reference', icon: Globe },
    { id: 'system', name: 'System', icon: Activity },
    { id: 'analytics', name: 'Analytics', icon: BarChart3 },
  ];

  const filteredEndpoints = endpoints.filter(endpoint => {
    const matchesSearch = searchTerm === '' || 
      endpoint.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
      endpoint.description.toLowerCase().includes(searchTerm.toLowerCase()) ||
      endpoint.endpoint.toLowerCase().includes(searchTerm.toLowerCase()) ||
      endpoint.tags.some(tag => tag.toLowerCase().includes(searchTerm.toLowerCase()));
    
    const matchesCategory = selectedCategory === 'all' || endpoint.category === selectedCategory;
    
    return matchesSearch && matchesCategory;
  });

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="space-y-3">
        <div className="flex items-center space-x-3">
          <div className="p-1.5 bg-primary-500/10 rounded-lg">
            <Book className="h-5 w-5 text-primary-400" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-white">API Documentation</h1>
            <p className="text-sm text-gray-400">Interactive documentation for the Auction System API</p>
          </div>
        </div>

        {/* API Info */}
        <div className="bg-gray-900 border border-gray-800 rounded-lg p-4">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <div className="text-center">
              <div className="text-xl font-bold text-primary-400">{endpoints.length}</div>
              <div className="text-xs text-gray-400">Endpoints</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-green-400">REST</div>
              <div className="text-xs text-gray-400">API Type</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-blue-400">JSON</div>
              <div className="text-xs text-gray-400">Response Format</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-yellow-400">2.0</div>
              <div className="text-xs text-gray-400">API Version</div>
            </div>
          </div>
        </div>

        {/* Base URL Info */}
        <div className="bg-gray-950 border border-gray-800 rounded-lg p-3">
          <h3 className="text-xs font-medium text-gray-300 mb-2">Base URL</h3>
          <CodeBlock 
            code={`${window.location.origin}/api`} 
            language="text" 
            showCopyButton={true}
            maxHeight="max-h-12"
          />
        </div>
      </div>

      {/* Search and Filters */}
      <div className="flex flex-col lg:flex-row space-y-3 lg:space-y-0 lg:space-x-3">
        {/* Search */}
        <div className="relative flex-1">
          <Search className="absolute left-2.5 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search endpoints..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-8 pr-3 py-2 bg-gray-900 border border-gray-700 rounded-lg text-sm text-gray-300 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
          />
        </div>

        {/* Category Filter */}
        <div className="flex space-x-1.5 overflow-x-auto">
          {categories.map((category) => {
            const Icon = category.icon;
            return (
              <button
                key={category.id}
                onClick={() => setSelectedCategory(category.id)}
                className={`flex items-center space-x-1.5 px-3 py-2 rounded-lg text-xs font-medium whitespace-nowrap transition-colors ${
                  selectedCategory === category.id
                    ? 'bg-primary-500 text-white'
                    : 'bg-gray-800 text-gray-300 hover:bg-gray-700'
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                <span>{category.name}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Results Count */}
      <div className="text-xs text-gray-500">
        Showing {filteredEndpoints.length} of {endpoints.length} endpoints
      </div>

      {/* Endpoints */}
      <div className="space-y-3">
        {filteredEndpoints.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <Search className="h-12 w-12 text-gray-600 mx-auto mb-3" />
            <h3 className="text-base font-medium mb-1">No endpoints found</h3>
            <p className="text-sm">Try adjusting your search terms or filters</p>
          </div>
        ) : (
          filteredEndpoints.map((endpoint, index) => (
            <ApiEndpoint
              key={index}
              title={endpoint.title}
              method={endpoint.method}
              endpoint={endpoint.endpoint}
              description={endpoint.description}
              parameters={endpoint.parameters}
              pathParams={endpoint.pathParams}
              responses={endpoint.responses}
              codeExamples={endpoint.codeExamples}
              tags={endpoint.tags}
            />
          ))
        )}
      </div>

      {/* Footer */}
      <div className="mt-8 pt-6 border-t border-gray-800 text-center">
        <div className="flex items-center justify-center space-x-3 text-xs text-gray-600">
          <span>API Docs</span>
          <span>•</span>
          <span>Interactive Documentation</span>
          <span>•</span>
          <span>Live API Testing</span>
        </div>
      </div>
    </div>
  );
};

export default ApiDocs;
