import React from 'react';
import { TrendingDown, ChevronRight } from 'lucide-react';
import type { AuctionListItem } from '../types/auction';
import { formatTimeAgo } from '../lib/utils';
import ChainIcon from './ChainIcon';
import TokensList from './TokensList';
import AddressLink from './AddressLink';
import InternalLink from './InternalLink';
import TokenPairDisplay from './TokenPairDisplay';
import MobileCard from './MobileCard';
import MobileAddressDisplay from './MobileAddressDisplay';
import { useKickableStatus } from '../hooks/useKickableStatus';

interface AuctionCardMobileProps {
  auction: AuctionListItem;
  kickableData?: Record<string, any>;
}

// Status configuration with colors and labels
const statusConfig = {
  kickable: {
    label: 'Kickable',
    textColor: 'text-purple-400',
    dotColor: 'bg-purple-500',
    animated: true,
  },
  active: {
    label: 'Active',
    textColor: 'text-success-400',
    dotColor: 'bg-success-500',
    animated: true,
  },
  inactive: {
    label: 'Inactive',
    textColor: 'text-gray-500',
    dotColor: 'bg-gray-600',
    animated: false,
  },
} as const;

export type AuctionStatus = 'active' | 'inactive' | 'kickable';

const AuctionCardMobile: React.FC<AuctionCardMobileProps> = ({ 
  auction,
  kickableData = {}
}) => {
  const currentRound = auction.current_round;
  const isActive = currentRound?.is_active || false;
  const isKickable = kickableData[auction.address]?.isKickable || false;
  const kickableCount = kickableData[auction.address]?.totalKickableCount || 0;

  // Determine all applicable statuses with ACTIVE prioritized at top
  const statuses: AuctionStatus[] = [];
  if (isActive) statuses.push('active');
  if (isKickable) statuses.push('kickable');
  if (statuses.length === 0) statuses.push('inactive');

  return (
    <MobileCard className="space-y-3">
      {/* Header: Chain + Address */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <ChainIcon 
            chainId={auction?.chain_id || 31337} 
            size="sm"
            showName={false}
          />
          <MobileAddressDisplay
            address={auction?.address || ''}
            chainId={auction?.chain_id || 1}
            type="address"
            variant="inline"
            showExternalLink={true}
            className="flex-1"
          />
        </div>
        <ChevronRight className="h-4 w-4 text-gray-500" />
      </div>

      {/* Status Row */}
      <div className="flex items-center justify-between">
        <div className="flex flex-col space-y-1">
          {statuses.map((status) => {
            const config = statusConfig[status];
            return (
              <div key={status} className="flex items-center space-x-2">
                <div className={`h-2 w-2 rounded-full ${config.dotColor} ${config.animated ? 'animate-pulse' : ''}`}></div>
                <span className={`text-sm font-medium ${config.textColor}`}>
                  {config.label}
                  {status === 'kickable' && kickableCount > 0 && (
                    <span className="text-xs ml-1">({kickableCount})</span>
                  )}
                </span>
              </div>
            );
          })}
        </div>

        {/* Round Info */}
        <div className="text-right">
          {currentRound ? (
            <InternalLink
              to={`/round/${auction?.chain_id}/${auction?.address}/${currentRound?.round_id}`}
              variant="round"
              className="text-primary-400 font-medium"
            >
              Round {currentRound.round_id}
            </InternalLink>
          ) : (
            <span className="text-gray-500 text-sm">No round</span>
          )}
        </div>
      </div>

      {/* Token Pair */}
      <div className="border-t border-gray-800 pt-3">
        <div className="text-xs text-gray-500 mb-1">Token Pair</div>
        <TokenPairDisplay
          fromToken={
            <TokensList 
              tokens={auction.from_tokens || []}
              maxDisplay={2}
              tokenClassName="text-gray-300 font-medium text-sm"
            />
          }
          toToken={auction.want_token?.symbol || '—'}
          size="sm"
        />
      </div>

      {/* Expandable Details */}
      <div className="border-t border-gray-800 pt-3 space-y-2">
        <div className="grid grid-cols-2 gap-4">
          {/* Decay Rate */}
          <div>
            <div className="text-xs text-gray-500 mb-1">Decay Rate</div>
            <div className="flex items-center space-x-1 text-sm">
              <TrendingDown className="h-3 w-3 text-gray-400" />
              <span className="font-medium text-gray-300">
                {auction.decay_rate !== undefined && auction.decay_rate !== null ? 
                  `${(auction.decay_rate * 100).toFixed(2)}%` : 
                  'N/A'
                }
              </span>
            </div>
          </div>

          {/* Update Interval */}
          <div>
            <div className="text-xs text-gray-500 mb-1">Update Interval</div>
            <span className="font-medium text-gray-300 text-sm">
              {auction.update_interval || 0}s
            </span>
          </div>
        </div>

        {/* Last Round */}
        <div>
          <div className="text-xs text-gray-500 mb-1">Last Round</div>
          {auction?.last_kicked ? (
            <span 
              className="text-sm text-gray-400"
              title={new Date(auction.last_kicked).toLocaleString()}
            >
              {formatTimeAgo(new Date(auction.last_kicked!).getTime() / 1000)}
            </span>
          ) : (
            <span className="text-gray-500 text-sm">—</span>
          )}
        </div>
      </div>
    </MobileCard>
  );
};

export default AuctionCardMobile;