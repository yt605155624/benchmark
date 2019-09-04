#!bin/bash
set -xe

if [[ $# -lt 2 ]]; then
    echo "Usage: "
    echo "  CUDA_VISIBLE_DEVICES=0 bash run.sh speed|mem|maxbs DCGAN|CGAN|Pix2pix sp|mp /ssd1/ljh/logs"
    exit
fi

function _set_params(){
    index="$1"
    model_name="$2"
    run_mode=${3:-"sp"}
    run_log_path=${4:-$(pwd)}

    skip_steps=5
    keyword="Batch_time_cost:"
    separator=":"
    position=-1
    model_mode=0

    device=${CUDA_VISIBLE_DEVICES//,/ }
    arr=($device)
    num_gpu_devices=${#arr[*]}

    base_batch_size=0

    log_file=${run_log_path}/${model_name}_${index}_${num_gpu_devices}_${run_mode}
    log_parse_file=${log_file}

}

function _set_env(){
    export FLAGS_cudnn_exhaustive_search=1
    export FLAGS_eager_delete_tensor_gb=0.0
}

function _train(){
    echo "Train on ${num_gpu_devices} GPUs"
    echo "current CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES, gpus=$num_gpu_devices"
    if echo {DCGAN CGAN} | grep -w $model_name &>/dev/null
    then
        base_batch_size=32
        echo "${model_name}, batch_size: ${base_batch_size}"
        train_cmd=" --model_net $model_name \
           --dataset mnist   \
           --noise_size 100  \
           --batch_size ${base_batch_size}   \
           --epoch 10"
    elif echo {Pix2pix} | grep -w $model_name &>/dev/null
    then
        base_batch_size=1
        echo "${model_name}, batch_size: ${base_batch_size}"
        train_cmd=" --model_net $model_name \
           --dataset cityscapes     \
           --train_list data/cityscapes/pix2pix_train_list \
           --test_list data/cityscapes/pix2pix_test_list    \
           --crop_type Random \
           --dropout True \
           --gan_mode vanilla \
           --batch_size ${base_batch_size} \
           --epoch 200 \
           --crop_size 256 "
    else
        echo "model: $model_name not support!"
    fi

    train_cmd="python -u train.py "${train_cmd}

    ${train_cmd} > ${log_file} 2>&1 &
    train_pid=$!
    sleep 120
    kill -9 $train_pid
}

function _run(){
    if [[ ${index} = "mem" ]]; then
        #若测试最大batchsize，FLAGS_fraction_of_gpu_memory_to_use=1
        export FLAGS_fraction_of_gpu_memory_to_use=0.001
        gpu_id=`echo $CUDA_VISIBLE_DEVICES | cut -c1`
        nvidia-smi --id=$gpu_id --query-compute-apps=used_memory --format=csv -lms 100 > gpu_use.log 2>&1 &
        gpu_memory_pid=$!
        _train
        kill ${gpu_memory_pid}
        awk 'BEGIN {max = 0} {if(NR>1){if ($1 > max) max=$1}} END {print "MAX_GPU_MEMORY_USE=", max}' gpu_use.log
    elif [[ ${index} = "speed" ]]; then
        job_bt=`date '+%Y%m%d%H%M%S'`
        _train
        job_et=`date '+%Y%m%d%H%M%S'`
        hostname=`echo $(hostname)|awk -F '.baidu.com' '{print $1}'`
        gpu_log_file=${log_file}_gpu
        cpu_log_file=${log_file}_cpu
        monquery -n ${hostname} -i GPU_AVERAGE_UTILIZATION -s $job_bt -e $job_et -d 60 > ${gpu_log_file}
        monquery -n ${hostname} -i CPU_USER -s $job_bt -e $job_et -d 60 > ${cpu_log_file}
        cpu_num=$(cat /proc/cpuinfo | grep processor | wc -l)
        gpu_num=$(nvidia-smi -L|wc -l)

        awk '{if(NR>1 && $3 >0){time+=$3;count+=1}} END{if(count>0) avg=time/count; else avg=0; printf("AVG_GPU_USE=%.2f\n" ,avg*'${gpu_num}')}' ${gpu_log_file}
        awk '{if(NR>1 && $3 >0){time+=$3;count+=1}} END{if(count>0) avg=time/count; else avg=0; printf("AVG_CPU_USE=%.2f\n" ,avg*'${cpu_num}')}' ${cpu_log_file}
    else
        _train
        error_string="Please shrink FLAGS_fraction_of_gpu_memory_to_use"
        if [ `grep -c "${error_string}" ${log_parse_file}` -eq 0 ]; then
            echo "MAX_BATCH_SIZE=${batch_size}"
        else
            echo "MAX_BATCH_SIZE=0"
        fi
    fi

    python ${BENCHMARK_ROOT}/utils/analysis.py \
            --filename ${log_file} \
            --keyword ${keyword} \
            --separator "${separator}" \
            --position ${position} \
            --base_batch_size ${base_batch_size} \
            --skip_steps ${skip_steps} \
            --model_mode ${model_mode} \
            --model_name ${model_name} \
            --run_mode ${run_mode} \
            --index ${index} \
            --gpu_num ${num_gpu_devices}
}

_set_params $@
_set_env
_run