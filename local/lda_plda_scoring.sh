#!/bin/bash
# Copyright 2015   David Snyder
#           2019   Lantian Li
# Apache 2.0.
#
# This script trains PLDA models and does scoring.

lda_dim=150
covar_factor=0.1
simple_length_norm=false # If true, replace the default length normalization
# performed in PLDA  by an alternative that
# normalizes the length of the iVectors to be equal
# to the square root of the iVector dimension.

#echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 5 ]; then
	echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <trials-file> <scores-dir>"
fi

plda_data_dir=$1
enroll_data_dir=$2
test_data_dir=$3
trials=$4
scores_dir=$5

mkdir -p $plda_data_dir/log
run.pl $plda_data_dir/log/compute_mean.log \
	ivector-mean ark:$plda_data_dir/xvector.ark \
	$plda_data_dir/mean.vec || exit 1;

run.pl $plda_data_dir/log/lda.log \
	ivector-compute-lda --total-covariance-factor=$covar_factor --dim=$lda_dim \
	"ark:ivector-subtract-global-mean ark:$plda_data_dir/xvector.ark ark:- |" \
	ark:$plda_data_dir/utt2spk $plda_data_dir/transform_lda.mat || exit 1;

run.pl $plda_data_dir/log/lda_plda.log \
	ivector-compute-plda ark:$plda_data_dir/spk2utt \
	"ark:ivector-subtract-global-mean ark:$plda_data_dir/xvector.ark ark:- | transform-vec $plda_data_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
	$plda_data_dir/lda_plda || exit 1;

mkdir -p $scores_dir/log
run.pl $scores_dir/log/lda_plda_scoring.log \
	ivector-plda-scoring --normalize-length=true \
	--num-utts=ark:${enroll_data_dir}/num_utts.ark \
	"ivector-copy-plda --smoothing=0.0 ${plda_data_dir}/lda_plda - |" \
	"ark:ivector-subtract-global-mean $plda_data_dir/mean.vec ark:$enroll_data_dir/xvector.ark ark:- | transform-vec $plda_data_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
	"ark:ivector-subtract-global-mean $plda_data_dir/mean.vec ark:$test_data_dir/xvector.ark ark:- | transform-vec $plda_data_dir/transform_lda.mat ark:- ark:- | ivector-normalize-length ark:- ark:- |" \
	"cat '$trials' | cut -d\  --fields=1,2 |" $scores_dir/lda_plda_scores || exit 1;

rm $plda_data_dir/{transform_lda.mat,lda_plda,mean.vec}
