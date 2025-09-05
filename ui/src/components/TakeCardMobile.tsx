import React from 'react';
import { ChevronRight, TrendingUp, TrendingDown } from 'lucide-react';
import type { AuctionTake } from '../types/auction';
import { formatReadableTokenAmount, formatUSD, formatTimeAgo, cn } from '../lib/utils';
import ChainIcon from './ChainIcon';
import AddressLink from './AddressLink';
import TakerLink from './TakerLink';
import RoundLink from './RoundLink';
import TakeLink from './TakeLink';
import RoundTakeDisplay from './RoundTakeDisplay';
import StandardTxHashLink from './StandardTxHashLink';
import TokenPairDisplay from './TokenPairDisplay';
import MobileCard from './MobileCard';
import MobileTxHashDisplay from './MobileTxHashDisplay';

interface TakeCardMobileProps {
  take: AuctionTake;
  showUSD?: boolean;
  hideAuctionColumn?: boolean;
  index: number;
}

const TakeCardMobile: React.FC<TakeCardMobileProps> = ({ 
  take, 
  showUSD = true,
  hideAuctionColumn = false,
  index
}) => {
  return (
    <MobileCard className="space-y-3">
      {/* Header: Chain + Round + Time */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <ChainIcon 
            chainId={take.chain_id} 
            size="sm"
            showName={false}
          />
          <RoundTakeDisplay
            chainId={take.chain_id}
            auctionAddress={take.auction}
            roundId={take.round_id}
            takeSeq={take.take_seq}
            size="sm"
          />
        </div>
        <span
          className="text-xs text-gray-400"
          title={take.timestamp ? new Date(take.timestamp).toLocaleString() : "Time unavailable"}
        >
          {take.timestamp ? formatTimeAgo(new Date(take.timestamp).getTime() / 1000) : "—"}
        </span>
      </div>

      {/* Token Pair & Value */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <TokenPairDisplay
            fromToken={take.from_token_symbol || 'FROM'}
            toToken={take.to_token_symbol || 'TO'}
            size="sm"
          />
          <div className="text-right">
            <div className="font-bold text-gray-100 text-sm">
              {showUSD ? (
                take.amount_taken_usd ? (
                  formatUSD(parseFloat(take.amount_taken_usd))
                ) : (
                  <span className="text-gray-500">—</span>
                )
              ) : (
                `${formatReadableTokenAmount(take.amount_taken, 4)} ${take.from_token_symbol || 'TOKEN'}`
              )}
            </div>
            <div className="text-xs text-gray-400">
              {showUSD ? (
                `${formatReadableTokenAmount(take.amount_taken, 3)} ${take.from_token_symbol || 'TOKEN'}`
              ) : (
                take.price && take.from_token_symbol && take.to_token_symbol ? (
                  `${formatReadableTokenAmount(take.price, 6)} ${take.to_token_symbol}/${take.from_token_symbol}`
                ) : (
                  take.amount_taken_usd ? formatUSD(parseFloat(take.amount_taken_usd)) : 'USD N/A'
                )
              )}
            </div>
          </div>
        </div>

        {/* Profit/Loss */}
        {take.price_differential_usd && take.price_differential_percent !== null && (
          <div className="flex items-center justify-center space-x-2 py-1 px-3 rounded-md bg-gray-800/50">
            {parseFloat(take.price_differential_usd) >= 0 ? (
              <TrendingUp className="h-4 w-4 text-green-400" />
            ) : (
              <TrendingDown className="h-4 w-4 text-red-400" />
            )}
            <div className="text-center">
              <div className={cn(
                "font-medium text-sm",
                parseFloat(take.price_differential_usd) >= 0 
                  ? "text-green-400" 
                  : "text-red-400"
              )}>
                {formatUSD(Math.abs(parseFloat(take.price_differential_usd)), 2)}
              </div>
              <div className={cn(
                "text-xs font-medium",
                parseFloat(take.price_differential_usd) >= 0 
                  ? "text-green-500" 
                  : "text-red-500"
              )}>
                {Math.abs(take.price_differential_percent).toFixed(2)}%
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Expandable Details */}
      <div className="border-t border-gray-800 pt-3 space-y-3">
        {/* Auction Address (if not hidden) */}
        {!hideAuctionColumn && (
          <div>
            <div className="text-xs text-gray-500 mb-1">Auction</div>
            <AddressLink
              address={take.auction}
              chainId={take.chain_id}
              type="auction"
              className="text-primary-400 text-sm"
            />
          </div>
        )}

        {/* Taker */}
        <div>
          <div className="text-xs text-gray-500 mb-1">Taker</div>
          <TakerLink
            takerAddress={take.taker}
            chainId={take.chain_id}
            className="text-gray-300 text-sm"
          />
        </div>

        {/* Transaction */}
        <div>
          <div className="text-xs text-gray-500 mb-1">Transaction</div>
          <MobileTxHashDisplay
            txHash={take.tx_hash}
            chainId={take.chain_id}
            variant="inline"
            className="text-sm"
          />
        </div>
      </div>
    </MobileCard>
  );
};

export default TakeCardMobile;