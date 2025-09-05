import React from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { 
  Activity,
  DollarSign,
  Fuel,
  TrendingUp,
  Clock,
  AlertCircle
} from 'lucide-react'
import { apiClient } from '../lib/api'
import StatsCard from '../components/StatsCard'
import LoadingSpinner from '../components/LoadingSpinner'
import BackButton from '../components/BackButton'
import ChainIcon from '../components/ChainIcon'
import CollapsibleSection from '../components/CollapsibleSection'
import KeyValueGrid from '../components/KeyValueGrid'
import PriceComparisonTable from '../components/PriceComparisonTable'
import TokenPairDisplay from '../components/TokenPairDisplay'
import RoundTakeDisplay from '../components/RoundTakeDisplay'
import TakerLink from '../components/TakerLink'
import InternalLink from '../components/InternalLink'
import StandardTxHashLink from '../components/StandardTxHashLink'
import AddressDisplay from '../components/AddressDisplay'
import { 
  formatUSD, 
  formatReadableTokenAmount,
  formatTimeAgo,
  formatAddress
} from '../lib/utils'

const TakeDetails: React.FC = () => {
  const { chainId, auctionAddress, roundId, takeSeq } = useParams<{
    chainId: string
    auctionAddress: string
    roundId: string
    takeSeq: string
  }>()

  const { data: takeDetails, isLoading, error } = useQuery({
    queryKey: ['takeDetails', chainId, auctionAddress, roundId, takeSeq],
    queryFn: () => apiClient.getTakeDetails(parseInt(chainId!), auctionAddress!, parseInt(roundId!), parseInt(takeSeq!)),
    enabled: !!chainId && !!auctionAddress && !!roundId && !!takeSeq,
    refetchInterval: 5 * 60 * 1000 // Refetch every 5 minutes
  })

  const [showGasUSD, setShowGasUSD] = React.useState(true)
  const [showRelativeTime, setShowRelativeTime] = React.useState(true)

  if (isLoading) {
    return (
      <div className="space-y-8">
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    )
  }

  if (error || !takeDetails) {
    return (
      <div className="card text-center py-12">
        <div className="w-16 h-16 bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-4">
          <AlertCircle className="h-8 w-8 text-gray-600" />
        </div>
        <h3 className="text-lg font-semibold text-gray-400 mb-2">Take Not Found</h3>
        <p className="text-gray-600 max-w-md mx-auto">
          The requested take details could not be found or loaded.
        </p>
        <div className="mt-4">
          <BackButton />
        </div>
      </div>
    )
  }

  // Group price quotes by token
  const fromTokenQuotes = takeDetails.price_quotes.filter(
    q => q.token_address.toLowerCase() === takeDetails.from_token.toLowerCase()
  )
  const toTokenQuotes = takeDetails.price_quotes.filter(
    q => q.token_address.toLowerCase() === takeDetails.to_token.toLowerCase()
  )

  const hasGasData = takeDetails.gas_used || takeDetails.transaction_fee_eth

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <BackButton />
          <div className="flex items-center space-x-3">
            <h1 className="text-2xl font-bold text-gray-100">Take Details</h1>
          </div>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatsCard
          title="Take Value"
          value={formatUSD(takeDetails.pnl_analysis.take_value_usd)}
          icon={DollarSign}
          iconColor="text-blue-400"
        />
        
        {hasGasData && (
          <div onClick={() => setShowGasUSD(prev => !prev)} className="cursor-pointer">
            <StatsCard
              title="Gas Cost"
              value={showGasUSD && takeDetails.transaction_fee_usd 
                ? formatUSD(takeDetails.transaction_fee_usd)
                : `${takeDetails.transaction_fee_eth?.toFixed(6)} ETH`
              }
              icon={Fuel}
              iconColor="text-gray-400"
            />
          </div>
        )}
        
        <StatsCard
          title="PnL Range"
          value={`${formatUSD(takeDetails.pnl_analysis.worst_case_pnl)} to ${formatUSD(takeDetails.pnl_analysis.best_case_pnl)}`}
          icon={TrendingUp}
          iconColor={takeDetails.pnl_analysis.base_pnl >= 0 ? "text-green-400" : "text-red-400"}
        />
        
        <div onClick={() => setShowRelativeTime(prev => !prev)} className="cursor-pointer">
          <StatsCard
            title="Time"
            value={showRelativeTime
              ? formatTimeAgo(new Date(takeDetails.timestamp).getTime() / 1000)
              : new Date(takeDetails.timestamp).toLocaleString()
            }
            icon={Clock}
            iconColor="text-gray-400"
          />
        </div>
      </div>

      {/* Core Information */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold">Take Info</h3>
          <ChainIcon chainId={takeDetails.chain_id} size="sm" showName={false} />
        </div>
        <KeyValueGrid items={[
          { label: "Pair", value: <span className="font-mono">{(takeDetails.from_token_symbol || 'FROM')} → {(takeDetails.to_token_symbol || 'TO')}</span> },
          { label: "Taker", value: <TakerLink takerAddress={takeDetails.taker} chainId={takeDetails.chain_id} /> },
          { label: "Transaction Hash", value: <StandardTxHashLink txHash={takeDetails.tx_hash} chainId={takeDetails.chain_id} /> },
          { label: "Auction", value: (
            <InternalLink 
              to={`/auction/${takeDetails.chain_id}/${takeDetails.auction_address}`} 
              variant="address"
              address={takeDetails.auction_address}
              chainId={takeDetails.chain_id}
            >
              {formatAddress(takeDetails.auction_address)}
            </InternalLink>
          ) },
          { label: "Round | Take", value: (
            <RoundTakeDisplay
              chainId={takeDetails.chain_id}
              auctionAddress={takeDetails.auction_address}
              roundId={takeDetails.round_id}
              takeSeq={takeDetails.take_seq}
              size="sm"
            />
          ) },
          { label: "Time", value: (
            <button className="text-left" onClick={() => setShowRelativeTime(prev => !prev)}>
              {showRelativeTime
                ? `${formatTimeAgo(new Date(takeDetails.timestamp).getTime() / 1000)}`
                : new Date(takeDetails.timestamp).toLocaleString()
              }
            </button>
          ) }
        ]} />
      </div>

      {/* Token Exchange Details */}
      <CollapsibleSection title="Token Exchange" defaultOpen={true}>
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* From Token (Taker Received) */}
            <div className="card bg-gray-800/50">
              <h4 className="font-semibold mb-2 text-gray-200">Taker Received</h4>
              <div className="space-y-1">
                <div className="flex justify-between">
                  <span className="text-gray-400">Amount:</span>
                  <span className="font-mono">{formatReadableTokenAmount(takeDetails.amount_taken)} {takeDetails.from_token_symbol}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">USD Value:</span>
                  <span className="font-mono">{formatUSD(takeDetails.pnl_analysis.take_value_usd)}</span>
                </div>
              </div>
            </div>

            {/* To Token (Auction Received) */}
            <div className="card bg-gray-800/50">
              <h4 className="font-semibold mb-2 text-gray-200">Auction Received</h4>
              <div className="space-y-1">
                <div className="flex justify-between">
                  <span className="text-gray-400">Amount:</span>
                  <span className="font-mono">{formatReadableTokenAmount(takeDetails.amount_paid)} {takeDetails.to_token_symbol}</span>
                </div>
                {typeof (takeDetails as any).want_token_price_usd === 'number' && (
                  <div className="flex justify-between">
                    <span className="text-gray-400">USD Value:</span>
                    <span className="font-mono">
                      {formatUSD(parseFloat(takeDetails.amount_paid) * (takeDetails as any).want_token_price_usd)}
                    </span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </CollapsibleSection>

      {/* Price Comparison Table */}
      {(fromTokenQuotes.length > 0 && toTokenQuotes.length > 0) && (
        <PriceComparisonTable
          fromTokenQuotes={fromTokenQuotes}
          toTokenQuotes={toTokenQuotes}
          amountTaken={parseFloat(takeDetails.amount_taken)}
          amountPaid={parseFloat(takeDetails.amount_paid)}
          fromTokenSymbol={takeDetails.from_token_symbol || 'FROM'}
          toTokenSymbol={takeDetails.to_token_symbol || 'TO'}
        />
      )}

      {/* Gas Analysis */}
      {hasGasData && (
        <CollapsibleSection title="Transaction cost" defaultOpen={true}>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {(() => {
              const baseOrGas = (typeof takeDetails.base_fee === 'number' ? takeDetails.base_fee : undefined) ??
                               (typeof takeDetails.gas_price === 'number' ? takeDetails.gas_price : undefined);
              return typeof baseOrGas === 'number' ? (
                <div className="bg-gray-800/50 p-2 rounded border border-gray-800">
                  <div className="text-xs text-gray-400 mb-1">Base Fee</div>
                  <div className="font-mono text-sm">{baseOrGas.toFixed(2)} Gwei</div>
                </div>
              ) : null;
            })()}
            {typeof takeDetails.priority_fee === 'number' && (
              <div className="bg-gray-800/50 p-2 rounded border border-gray-800">
                <div className="text-xs text-gray-400 mb-1">Priority Fee</div>
                <div className="font-mono text-sm">{takeDetails.priority_fee.toFixed(4)} Gwei</div>
              </div>
            )}
            {typeof takeDetails.gas_used === 'number' && (
              <div className="bg-gray-800/50 p-2 rounded border border-gray-800">
                <div className="text-xs text-gray-400 mb-1">Gas Used</div>
                <div className="font-mono text-sm">{takeDetails.gas_used.toLocaleString()}</div>
              </div>
            )}
            {typeof takeDetails.transaction_fee_usd === 'number' && (
              <div className="bg-gray-800/50 p-2 rounded border border-gray-800">
                <div className="text-xs text-gray-400 mb-1">Total Fee</div>
                <div className="font-mono text-sm">{formatUSD(takeDetails.transaction_fee_usd)}</div>
                {typeof takeDetails.transaction_fee_eth === 'number' && (
                  <div className="text-xs text-gray-500 font-mono">{takeDetails.transaction_fee_eth.toFixed(6)} ETH</div>
                )}
              </div>
            )}
            {takeDetails.pnl_analysis.take_value_usd > 0 && takeDetails.transaction_fee_usd && (
              <div className="bg-gray-800/50 p-2 rounded border border-gray-800">
                <div className="text-xs text-gray-400 mb-1">Fee %</div>
                <div className="font-mono text-sm">{((takeDetails.transaction_fee_usd / takeDetails.pnl_analysis.take_value_usd) * 100).toFixed(3)}%</div>
              </div>
            )}
          </div>
        </CollapsibleSection>
      )}

    </div>
  )
}

export default TakeDetails
