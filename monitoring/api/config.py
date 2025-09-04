#!/usr/bin/env python3
"""
Configuration management for Auction API.
Supports mock, development, and production modes.
"""

import os
from enum import Enum
from typing import Optional
from dotenv import load_dotenv

# Load environment variables from .env file
# Try different paths to work from both project root and api directory
import pathlib
config_dir = pathlib.Path(__file__).parent
project_root = config_dir.parent.parent
env_file = project_root / ".env"
load_dotenv(str(env_file))


class AppMode(str, Enum):
    """Application running modes"""
    MOCK = "mock"
    DEV = "dev"
    DEVELOPMENT = "development" 
    PRODUCTION = "production"
    PROD = "prod"  # Alias for production


class Settings:
    """Application settings with environment-based configuration"""
    
    def __init__(self):
        # Application mode
        mode_str = os.getenv("APP_MODE", "mock").lower()
        try:
            self.app_mode = AppMode(mode_str)
        except ValueError:
            self.app_mode = AppMode.MOCK
        
        # API settings
        self.api_host = os.getenv("API_HOST", "0.0.0.0")
        self.api_port = int(os.getenv("API_PORT", "8000"))
        self.cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000")
        
        # Database settings (only used in development/production)
        self.database_url = os.getenv("DATABASE_URL")
        
        # Mode-specific database URLs
        self.dev_database_url = os.getenv("DEV_DATABASE_URL")
        self.prod_database_url = os.getenv("DATABASE_URL")
        self.mock_database_url = os.getenv("MOCK_DATABASE_URL")
        
        # Blockchain settings (legacy - for backwards compatibility)
        self.anvil_rpc_url = os.getenv("ANVIL_RPC_URL", "http://localhost:8545")
        self.web3_infura_project_id = os.getenv("WEB3_INFURA_PROJECT_ID")
        
        # Mode-specific Anvil RPC URLs
        self.dev_anvil_rpc_url = os.getenv("DEV_ANVIL_RPC_URL")
        
        # Rindexer settings (only used in development/production)
        self.rindexer_database_url = os.getenv("RINDEXER_DATABASE_URL")
        self.rindexer_rpc_url = os.getenv("RINDEXER_RPC_URL", "http://localhost:8545")
        
        # Factory contract settings (legacy - for backwards compatibility)
        self.factory_address = os.getenv("FACTORY_ADDRESS")
        
        # Mode-specific network configurations
        self.dev_networks_enabled = os.getenv("DEV_NETWORKS_ENABLED", "local")
        self.prod_networks_enabled = os.getenv("NETWORKS_ENABLED", "ethereum,polygon,arbitrum,optimism,base")
        self.mock_networks_enabled = os.getenv("MOCK_NETWORKS_ENABLED", "ethereum,polygon,arbitrum,optimism,base,local")
        
        # Set networks based on app mode
        app_mode = os.getenv("APP_MODE", "dev")
        if app_mode == "prod":
            self.networks_enabled = self.prod_networks_enabled
        elif app_mode == "mock":
            self.networks_enabled = self.mock_networks_enabled
        else:  # dev mode
            self.networks_enabled = self.dev_networks_enabled
        
        # Network-specific RPC URLs
        self.ethereum_rpc_url = os.getenv("ETHEREUM_RPC_URL")
        self.polygon_rpc_url = os.getenv("POLYGON_RPC_URL")
        self.arbitrum_rpc_url = os.getenv("ARBITRUM_RPC_URL")
        self.optimism_rpc_url = os.getenv("OPTIMISM_RPC_URL")
        self.base_rpc_url = os.getenv("BASE_RPC_URL")
        
        # Network-specific factory addresses
        self.ethereum_factory_address = os.getenv("ETHEREUM_FACTORY_ADDRESS")
        self.polygon_factory_address = os.getenv("POLYGON_FACTORY_ADDRESS")
        self.arbitrum_factory_address = os.getenv("ARBITRUM_FACTORY_ADDRESS")
        self.optimism_factory_address = os.getenv("OPTIMISM_FACTORY_ADDRESS")
        self.base_factory_address = os.getenv("BASE_FACTORY_ADDRESS")
        self.local_factory_address = os.getenv("LOCAL_FACTORY_ADDRESS")
        
    
    
    def get_effective_database_url(self) -> Optional[str]:
        """Get the effective database URL based on app mode"""
        # First try the generic database_url
        if self.database_url:
            return self.database_url
            
        # Then try mode-specific URLs
        if self.app_mode in [AppMode.DEV, AppMode.DEVELOPMENT]:
            return self.dev_database_url
        elif self.app_mode in [AppMode.PRODUCTION, AppMode.PROD]:
            return self.prod_database_url  
        elif self.app_mode == AppMode.MOCK:
            return self.mock_database_url
            
        return None
    
    def get_effective_networks_enabled(self) -> str:
        """Get the effective networks enabled based on app mode"""
        # First try the generic networks_enabled
        if self.networks_enabled:
            return self.networks_enabled
            
        # Then try mode-specific networks
        if self.app_mode in [AppMode.DEV, AppMode.DEVELOPMENT]:
            return self.dev_networks_enabled or "local"
        elif self.app_mode in [AppMode.PRODUCTION, AppMode.PROD]:
            return self.prod_networks_enabled or "ethereum,polygon,arbitrum,optimism,base"
        elif self.app_mode == AppMode.MOCK:
            return self.mock_networks_enabled or "ethereum,polygon,arbitrum,optimism,base,local"
            
        return "local"


# Global settings instance
settings = Settings()


def get_settings() -> Settings:
    """Get application settings"""
    return settings


def is_mock_mode() -> bool:
    """Check if running in mock mode"""
    return settings.app_mode == AppMode.MOCK


def is_development_mode() -> bool:
    """Check if running in development mode"""
    return settings.app_mode in [AppMode.DEVELOPMENT, AppMode.DEV]


def is_production_mode() -> bool:
    """Check if running in production mode"""
    return settings.app_mode in [AppMode.PRODUCTION, AppMode.PROD]


def requires_database() -> bool:
    """Check if current mode requires database connection"""
    return settings.app_mode in [AppMode.DEVELOPMENT, AppMode.DEV, AppMode.PRODUCTION]


def get_cors_origins() -> list:
    """Get CORS origins as a list"""
    return [origin.strip() for origin in settings.cors_origins.split(",")]


# Network definitions with metadata
SUPPORTED_NETWORKS = {
    "ethereum": {
        "chain_id": 1,
        "name": "Ethereum Mainnet",
        "short_name": "Ethereum",
        "rpc_key": "ethereum_rpc_url",
        "factory_key": "ethereum_factory_address",
        "explorer": "https://etherscan.io",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_ethereum.jpg"
    },
    "polygon": {
        "chain_id": 137,
        "name": "Polygon",
        "short_name": "Polygon",
        "rpc_key": "polygon_rpc_url",
        "factory_key": "polygon_factory_address",
        "explorer": "https://polygonscan.com",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_polygon.jpg"
    },
    "arbitrum": {
        "chain_id": 42161,
        "name": "Arbitrum One",
        "short_name": "Arbitrum",
        "rpc_key": "arbitrum_rpc_url",
        "factory_key": "arbitrum_factory_address",
        "explorer": "https://arbiscan.io",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_arbitrum.jpg"
    },
    "optimism": {
        "chain_id": 10,
        "name": "Optimism",
        "short_name": "Optimism",
        "rpc_key": "optimism_rpc_url",
        "factory_key": "optimism_factory_address",
        "explorer": "https://optimistic.etherscan.io",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_optimism.jpg"
    },
    "base": {
        "chain_id": 8453,
        "name": "Base",
        "short_name": "Base",
        "rpc_key": "base_rpc_url",
        "factory_key": "base_factory_address",
        "explorer": "https://basescan.org",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_base.jpg"
    },
    "local": {
        "chain_id": 31337,
        "name": "Anvil Local",
        "short_name": "Anvil",
        "rpc_key": "anvil_rpc_url",  # Uses legacy key for backwards compatibility
        "factory_key": "local_factory_address",
        "explorer": "#",
        "icon": "https://icons.llamao.fi/icons/chains/rsz_ethereum.jpg"
    }
}


def get_enabled_networks() -> list:
    """Get list of enabled network names"""
    networks_enabled = settings.get_effective_networks_enabled()
    if not networks_enabled:
        return []
    return [name.strip() for name in networks_enabled.split(",") if name.strip()]


def get_network_config(network_name: str) -> dict:
    """Get configuration for a specific network"""
    if network_name not in SUPPORTED_NETWORKS:
        raise ValueError(f"Unsupported network: {network_name}")
    
    network_meta = SUPPORTED_NETWORKS[network_name]
    config = network_meta.copy()
    
    # Add actual values from settings
    config["rpc_url"] = getattr(settings, network_meta["rpc_key"], None)
    config["factory_address"] = getattr(settings, network_meta["factory_key"], None)
    
    return config


def get_all_network_configs() -> dict:
    """Get configurations for all enabled networks"""
    enabled = get_enabled_networks()
    return {
        name: get_network_config(name) 
        for name in enabled 
        if name in SUPPORTED_NETWORKS
    }


def validate_settings():
    """Validate settings based on app mode"""
    if requires_database():
        effective_db_url = settings.get_effective_database_url()
        if not effective_db_url:
            raise ValueError(f"Database URL is required for {settings.app_mode} mode")
        
        # Note: RINDEXER_DATABASE_URL validation removed - it's optional for API operation
    
    # Note: Network validation disabled for API - networks are only needed for indexer
    # if not is_mock_mode():
    #     enabled_networks = get_enabled_networks()
    #     for network_name in enabled_networks:
    #         if network_name not in SUPPORTED_NETWORKS:
    #             raise ValueError(f"Unknown network '{network_name}' in NETWORKS_ENABLED")
    #         
    #         network_config = get_network_config(network_name)
    #         if not network_config.get("rpc_url"):
    #             raise ValueError(f"RPC URL is required for network '{network_name}'")


# Validate on import
validate_settings()