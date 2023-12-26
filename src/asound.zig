pub const ASoundError = error{
    PCMOpenFailed,
    PCMHWParamsError,
    PCMPrepareError,
    PCMReadError,
    PCMWriteError,
    PCMCloseError,
};

pub const DefaultDevice = "default";
