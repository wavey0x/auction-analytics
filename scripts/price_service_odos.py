#!/usr/bin/env python3
"""
Odos Price Service
Polls for recent takes and fetches current token prices from Odos API
"""

import os
import sys
import time
import logging
import psycopg2
import psycopg2.extras
import requests
import argparse
from decimal import Decimal
from datetime import datetime, timedelta
from typing import Optional, Dict, List, Set
from dotenv import load_dotenv

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class OdosPriceService:
    """Price service using Odos API to fetch current token prices"""
    
    def __init__(self, poll_interval: int = 6, recency_minutes: int = None, once: bool = False):
        self.db_conn = None
        self.poll_interval = max(1, int(poll_interval))
        
        # Use environment-specific max age configuration if recency_minutes not provided
        if recency_minutes is None:
            app_mode = os.getenv('APP_MODE', 'dev').lower()
            env_key = f"{app_mode.upper()}_QUOTE_API_MAX_AGE_MINUTES"
            self.recency_minutes = int(os.getenv(env_key, '10'))
        else:
            self.recency_minutes = recency_minutes
            
        self.once = once
        self.api_key = os.getenv('ODOS_API_KEY')
        self.base_url = "https://api.odos.xyz/pricing/token"
        self.chain_names = {
            1: "1",  # Mainnet
            137: "137",  # Polygon
            42161: "42161",  # Arbitrum
            10: "10",  # Optimism
            8453: "8453",  # Base
        }
        # Removed processed_takes tracking - now using database status
        self._init_database()
        
    def _init_database(self) -> None:
        """Initialize database connection"""
        try:
            # Use the same database URL as other services
            app_mode = os.getenv('APP_MODE', 'dev').lower()
            if app_mode == 'dev':
                db_url = os.getenv('DEV_DATABASE_URL', 'postgresql://postgres:password@localhost:5433/auction_dev')
            elif app_mode == 'prod':
                db_url = os.getenv('PROD_DATABASE_URL')
            else:
                logger.error(f"Unsupported APP_MODE for price service: {app_mode}")
                sys.exit(1)
                
            if not db_url:
                logger.error("No database URL configured")
                sys.exit(1)
                
            self.db_conn = psycopg2.connect(db_url, cursor_factory=psycopg2.extras.RealDictCursor)
            self.db_conn.autocommit = True
            logger.info("✅ Database connection established")
            
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            sys.exit(1)
    
    def get_fresh_price_requests(self) -> List[Dict]:
        """Get recent price requests that are within recency window and not processed yet"""
        try:
            with self.db_conn.cursor() as cursor:
                # Get current time for freshness check
                current_time = int(time.time())
                
                # Select pending requests that are fresh enough for quote APIs
                cursor.execute("""
                    SELECT pr.id, pr.chain_id, pr.block_number, pr.token_address, 
                           pr.request_type, pr.auction_address, pr.round_id, pr.txn_timestamp
                    FROM price_requests pr
                    WHERE pr.status = 'pending'
                      AND pr.chain_id IN %s
                      AND pr.txn_timestamp IS NOT NULL
                      AND (%s - pr.txn_timestamp) <= %s  -- Within recency window (seconds)
                    ORDER BY pr.txn_timestamp DESC
                    LIMIT 100
                """, (
                    tuple(self.chain_names.keys()),
                    current_time,
                    self.recency_minutes * 60
                ))
                
                requests = cursor.fetchall()
                
                if requests:
                    logger.info(f"[ODOS] Found {len(requests)} fresh price requests (< {self.recency_minutes} minutes old)")
                
                return requests
                
        except Exception as e:
            logger.error(f"Failed to get fresh price requests: {e}")
            return []
    
    def fetch_token_price(self, token_address: str, chain_id: int) -> Optional[Decimal]:
        """Fetch current price for a token from Odos API"""
        if chain_id not in self.chain_names:
            logger.debug(f"Chain {chain_id} not supported by Odos")
            return None
            
        # Skip ETH - only ypricemagic should handle ETH pricing
        if token_address.lower() == "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee":
            logger.debug(f"Skipping ETH price request - handled by ypricemagic only")
            return None
            
        try:
            # Odos API endpoint
            url = f"{self.base_url}/{self.chain_names[chain_id]}/{token_address}"
            
            headers = {}
            if self.api_key:
                headers['X-API-KEY'] = self.api_key
            
            response = requests.get(url, headers=headers, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                
                # Parse response - adjust based on actual Odos API format
                if 'tokenPrices' in data and token_address.lower() in data['tokenPrices']:
                    price_data = data['tokenPrices'][token_address.lower()]
                    price = price_data.get('price')
                    if price:
                        return Decimal(str(price))
                elif 'price' in data:
                    return Decimal(str(data['price']))
                    
            elif response.status_code == 429:
                logger.warning(f"Rate limit hit for Odos API")
                time.sleep(1)  # Brief pause on rate limit
            else:
                logger.debug(f"Odos API returned status {response.status_code} for {token_address}")
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Odos API request failed for {token_address}: {e}")
        except Exception as e:
            logger.error(f"Failed to parse Odos response for {token_address}: {e}")
            
        return None
    
    def store_price(self, chain_id: int, token_address: str, price_usd: Decimal, block_number: int, txn_timestamp: int = None) -> None:
        """Store token price in database with transaction timestamp"""
        try:
            with self.db_conn.cursor() as cursor:
                # Store with current timestamp since Odos provides current prices
                cursor.execute("""
                    INSERT INTO token_prices (
                        chain_id, block_number, token_address, 
                        price_usd, timestamp, txn_timestamp, source, created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, 'odos', NOW())
                """, (
                    chain_id, 
                    block_number,  # Store the block from the price request
                    token_address, 
                    price_usd,
                    int(time.time()),  # Current timestamp for when price was fetched
                    txn_timestamp  # Original transaction timestamp
                ))
                
                if cursor.rowcount > 0:
                    logger.info(f"[ODOS] 💰 Stored price: {token_address[:6]}..{token_address[-4:]} = ${price_usd:.4f}")
                    
        except Exception as e:
            logger.error(f"Failed to store price for {token_address}: {e}")
    
    def mark_request_completed(self, request_id: int) -> None:
        """Mark a price request as completed"""
        try:
            with self.db_conn.cursor() as cursor:
                cursor.execute("""
                    UPDATE price_requests 
                    SET status = 'completed', processed_at = NOW() 
                    WHERE id = %s
                """, (request_id,))
        except Exception as e:
            logger.error(f"Failed to mark request {request_id} as completed: {e}")
    
    def mark_request_failed(self, request_id: int, error_message: str) -> None:
        """Mark a price request as failed"""
        try:
            with self.db_conn.cursor() as cursor:
                cursor.execute("""
                    UPDATE price_requests 
                    SET status = 'failed', error_message = %s, processed_at = NOW(),
                        retry_count = retry_count + 1
                    WHERE id = %s
                """, (error_message[:500], request_id))  # Truncate error message
        except Exception as e:
            logger.error(f"Failed to mark request {request_id} as failed: {e}")
    
    def process_price_request(self, request: Dict) -> None:
        """Process a single price request"""
        try:
            request_id = request['id']
            chain_id = request['chain_id']
            token_address = request['token_address']
            block_number = request['block_number']
            txn_timestamp = request['txn_timestamp']
            
            logger.debug(f"Processing request {request_id} for token {token_address[:6]}..{token_address[-4:]} on chain {chain_id}")
            
            # Fetch price for the token
            price = self.fetch_token_price(token_address, chain_id)
            
            if price is not None:
                # Store price with transaction timestamp
                self.store_price(chain_id, token_address, price, block_number, txn_timestamp)
                # Mark request as completed
                self.mark_request_completed(request_id)
                logger.info(f"[ODOS] ✅ Completed request {request_id}: {token_address[:6]}..{token_address[-4:]} = ${price:.4f}")
            else:
                # Mark request as failed
                self.mark_request_failed(request_id, "Failed to fetch price from ODOS API")
                logger.warning(f"[ODOS] ❌ Failed request {request_id}: No price available for {token_address[:6]}..{token_address[-4:]}")
                
        except Exception as e:
            logger.error(f"Failed to process price request {request.get('id', 'unknown')}: {e}")
            # Mark as failed if we have the request_id
            if 'id' in request:
                self.mark_request_failed(request['id'], str(e))
    
    def run_polling_loop(self) -> None:
        """Main polling loop"""
        logger.info("🚀 Starting Odos Price Service")
        logger.info(f"📊 Settings: poll_interval={self.poll_interval}s, recency_minutes={self.recency_minutes}")
        
        if self.api_key:
            logger.info("🔑 Odos API key configured")
        else:
            logger.warning("⚠️  No Odos API key configured - may hit rate limits")
        
        while True:
            try:
                # Get fresh price requests within recency window
                fresh_requests = self.get_fresh_price_requests()
                
                if fresh_requests:
                    for request in fresh_requests:
                        self.process_price_request(request)
                        # Small delay between requests to avoid rate limits
                        time.sleep(0.1)
                else:
                    logger.debug(f"[ODOS] No fresh price requests found (within {self.recency_minutes} minutes)")
                
                if self.once:
                    logger.info("✅ Single cycle completed (--once mode)")
                    break
                
                # Wait before next poll
                logger.debug(f"[ODOS] Sleeping for {self.poll_interval} seconds...")
                time.sleep(self.poll_interval)
                
            except KeyboardInterrupt:
                logger.info("\n🛑 Stopping Odos price service...")
                break
            except Exception as e:
                logger.error(f"Error in polling loop: {e}")
                if not self.once:
                    time.sleep(self.poll_interval)
                else:
                    break

def main():
    parser = argparse.ArgumentParser(description='Odos Price Service')
    parser.add_argument('--poll-interval', type=int, default=6, 
                       help='Poll interval in seconds (default: 6)')
    parser.add_argument('--recency-minutes', type=int, default=10,
                       help='How recent takes must be in minutes (default: 10)')
    parser.add_argument('--once', action='store_true',
                       help='Run once and exit')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug logging')
    
    args = parser.parse_args()
    
    # Set debug logging if requested
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.setLevel(logging.DEBUG)
    
    service = OdosPriceService(
        poll_interval=args.poll_interval,
        recency_minutes=args.recency_minutes,
        once=args.once
    )
    
    try:
        service.run_polling_loop()
    except Exception as e:
        logger.error(f"Service failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()