{-# LANGUAGE TypeFamilies #-}

-- | Decaying Flow Agreement (DFA)
--
-- NOTE: The formulas can be obtained from the output of maths/DFA.py
module Money.Systems.Superfluid.Agreements.DecayingFlowAgreement
    ( AgreementContractData (..)
    , AgreementAccountData (..)
    , AgreementParties (..)
    , DFAContractData
    , DFAAccountData
    ) where

import           Data.Default                                            (Default (..))
import           Data.Kind                                               (Type)
import           Data.Type.TaggedTypeable

import           Money.Systems.Superfluid.Concepts.Agreement             (Agreement (..))
import           Money.Systems.Superfluid.Concepts.Liquidity             (UntappedLiquidity (..), mkAnyTappedLiquidity)
import           Money.Systems.Superfluid.Concepts.RealtimeBalance
    ( RealtimeBalance (..)
    , TypedLiquidityVector (..)
    )
import           Money.Systems.Superfluid.Concepts.SuperfluidTypes
--
import qualified Money.Systems.Superfluid.SubSystems.BufferBasedSolvency as BBS


default_lambda :: RealFloat b => b
default_lambda = log 2 / (3600 * 24 * 7)

type DFA :: Type -> Type
data DFA sft
type DFAContractData sft = AgreementContractData (DFA sft)
type DFAAccountData sft = AgreementAccountData (DFA sft)
instance SuperfluidTypes sft => Agreement (DFA sft) where
    type DistributionForAgreement (DFA sft) = sft
    data AgreementContractData (DFA sft) = DFAContractData
        { flowLastUpdatedAt :: SFT_TS sft
        , decayingFactor    :: SFT_FLOAT sft
        , distributionLimit :: SFT_LQ sft
        , flowBuffer        :: BBS.BufferLiquidity (SFT_LQ sft)
        }
    data AgreementAccountData (DFA sft) = DFAAccountData
        { settledAt     :: SFT_TS sft
        , αVal          :: SFT_FLOAT sft
        , εVal          :: SFT_FLOAT sft
        , settledBuffer :: BBS.BufferLiquidity (SFT_LQ sft)
        }
    data AgreementParties (DFA sft) = DFAParties (DFAAccountData sft) (DFAAccountData sft)

    -- | Provided balance by DFA
    --
    -- Formula:
    --   rtb(aad, t) = α * e ^ (-λ * (t - t_s)) + ε
    --       where { t_s = t_s, αVal = α, εVal = ε } = aad
    providedBalanceByAgreement DFAAccountData
        { settledAt = t_s, αVal = α, εVal = ε, settledBuffer = buf_s } t =
        typedLiquidityVectorToRTB $ TypedLiquidityVector
            ( UntappedLiquidity $ ceiling $ α * exp (-λ * t_Δ) + ε )
            [ mkAnyTappedLiquidity buf_s ]
        where λ = default_lambda
              t_Δ = fromIntegral (t - t_s)

    -- | Create data of agreement parties from the changes of the DFA contract
    --
    -- Formula:
    --   aad_mempty_update_with_acd(aad, θ_Δ, t_u) = DFA_AAD { t_s = t_u , α = θ_Δ , ε = -θ_Δ }
    createAgreementParties old new = DFAParties
        DFAAccountData { settledAt = t', αVal = θ_Δ, εVal = -θ_Δ, settledBuffer = flowBufferDelta }
        DFAAccountData { settledAt = t', αVal = -θ_Δ, εVal = θ_Δ, settledBuffer = def }
        where
            t' = flowLastUpdatedAt new
            θ_Δ = fromIntegral (distributionLimit new - distributionLimit old)
            flowBufferDelta = flowBuffer new - flowBuffer old

    unionAgreementPartiesWith f (DFAParties s r) (DFAParties s' r') = DFAParties (f s s') (f r r')

instance SuperfluidTypes sft => TaggedTypeable (DFAContractData sft) where tagFromProxy _ = "DFA#"

instance SuperfluidTypes sft => Default (DFAContractData sft) where
    def = DFAContractData
        { flowLastUpdatedAt = def
        , decayingFactor = default_lambda
        , distributionLimit = def
        , flowBuffer = def
        }

instance SuperfluidTypes sft => TaggedTypeable (DFAAccountData sft) where tagFromProxy _ = "DFA"
instance SuperfluidTypes sft => Default (DFAAccountData sft) where
    def = DFAAccountData
        { settledAt = def
        , αVal = def
        , εVal = def
        , settledBuffer = def
        }
instance SuperfluidTypes sft => Semigroup (DFAAccountData sft) where
    -- Formula:
    --   aad_mappend(a, b) = DFA_AAD
    --     { t_s = t_s'
    --     , α = α * e ^ (λ * (t_s - t_s')) - ε'
    --     , ε = ε + ε'
    --     }
    --     where { t_s = t_s, αVal = α, εVal = ε } = a
    --           { t_s = t_s', αVal = α', εVal = ε' } = b
    (<>) a b = DFAAccountData
        { settledAt = settledAt b
        , αVal = (αVal a) * exp (-λ * t_Δ) - εVal b
        , εVal = εVal a + εVal b
        , settledBuffer = settledBuffer a + settledBuffer b
        }
        where λ = default_lambda
              t_Δ = fromIntegral (settledAt b - settledAt a)