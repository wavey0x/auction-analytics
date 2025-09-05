import { Token } from "../types/auction";
import TokenWithAddress from "./TokenWithAddress";

interface KickableToken {
  address: string;
  symbol: string;
  kickableAmount: bigint;
}

interface ExpandedTokensListProps {
  tokens: Token[];
  chainId: number;
  className?: string;
  kickableTokens?: KickableToken[];
}

const ExpandedTokensList: React.FC<ExpandedTokensListProps> = ({
  tokens,
  chainId,
  className = "",
  kickableTokens = [],
}) => {
  // Check if a token is kickable
  const isTokenKickable = (tokenAddress: string) => {
    const result = kickableTokens.some(kt => kt.address.toLowerCase() === tokenAddress.toLowerCase());
    return result;
  };

  return (
    <div className={className}>
      {/* Token Grid - More space without search bar */}
      <div className="max-h-64 overflow-y-auto">
        <div className="grid grid-cols-3 gap-2">
          {tokens.length > 0 ? (
            tokens.map((token) => {
              const kickable = isTokenKickable(token.address);
              return (
                <TokenWithAddress
                  key={token.address}
                  token={token}
                  chainId={chainId}
                  textColor={kickable ? "text-purple-400" : "text-white"}
                />
              );
            })
          ) : (
            <div className="col-span-3 text-center py-4 text-gray-500 text-sm">
              No tokens available
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default ExpandedTokensList;