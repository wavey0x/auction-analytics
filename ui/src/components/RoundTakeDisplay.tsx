import React from 'react';
import RoundLink from './RoundLink';
import TakeLink from './TakeLink';

interface RoundTakeDisplayProps {
  chainId: number;
  auctionAddress: string;
  roundId: number;
  takeSeq: number;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

/**
 * Ultra-compact display for Round + Take buttons side by side
 * Saves space by eliminating separator and keeping buttons tight together
 */
const RoundTakeDisplay: React.FC<RoundTakeDisplayProps> = ({
  chainId,
  auctionAddress,
  roundId,
  takeSeq,
  size = 'sm',
  className = ''
}) => {
  return (
    <div className={`inline-flex items-center space-x-1 ${className}`}>
      <RoundLink
        chainId={chainId}
        auctionAddress={auctionAddress}
        roundId={roundId}
        size={size}
        showArrow={false}
      />
      <TakeLink
        chainId={chainId}
        auctionAddress={auctionAddress}
        roundId={roundId}
        takeSeq={takeSeq}
        variant="minimal"
        size={size}
        showArrow={false}
      />
    </div>
  );
};

export default RoundTakeDisplay;